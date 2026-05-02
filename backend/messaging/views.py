"""1:1 direct-messaging endpoints.

Surface:
  GET    /messages/threads/                       — inbox list
  GET    /messages/unread-count/                  — total unread for badge
  POST   /messages/threads/with/<prof_id>/        — start (or get existing) thread
  GET    /messages/threads/<id>/                  — paginated messages
  POST   /messages/threads/<id>/messages/         — send a message
  POST   /messages/threads/<id>/read/             — mark all read up to now

Block check: if EITHER side has the OTHER in their `ConsultantBlocklist`,
starting a thread or sending a message is rejected (HTTP 403). Reusing the
existing blocklist so users get one place to silence someone.
"""
import logging

from django.db.models import Count, Max, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from accounts.models import DeviceToken, MedicalProfessional
from accounts.permissions import IsAdminVerified
from consultants.models import ConsultantBlocklist
from medunity.fcm import send_push_notification

from .models import DirectMessage, DirectMessageHide, DirectThread, ThreadReadState

logger = logging.getLogger(__name__)

PAGE_SIZE = 50
MAX_BODY_LEN = 4000


# ── Helpers ───────────────────────────────────────────────────────────────────

def _is_blocked_between(p1, p2) -> bool:
    """True if either side blocked the other via ConsultantBlocklist.

    Symmetric — blocking from any side stops messaging both ways.
    """
    return ConsultantBlocklist.objects.filter(
        Q(consultant=p1, doctor=p2) | Q(consultant=p2, doctor=p1)
    ).exists()


def _doctor_card(prof) -> dict:
    try:
        spec_display = prof.get_specialization_display()
    except Exception:
        spec_display = ''
    return {
        'id': prof.id,
        'full_name': prof.full_name,
        'specialization_display': spec_display,
        'profile_photo': (prof.profile_photo.url if prof.profile_photo else None),
    }


def _read_state_for(thread, prof):
    return ThreadReadState.objects.filter(thread=thread, professional=prof).first()


def _hidden_message_ids_for(thread, prof) -> set:
    return set(
        DirectMessageHide.objects
        .filter(message__thread=thread, professional=prof)
        .values_list('message_id', flat=True)
    )


def _visible_messages_qs(thread, prof):
    """Messages still visible to `prof` after applying per-side deletes.

    - Drops messages individually hidden via DirectMessageHide.
    - Drops everything older than the per-side `deleted_at` (Delete-for-me on
      the whole thread), if such a marker exists.
    """
    qs = thread.messages.all()
    state = _read_state_for(thread, prof)
    if state and state.deleted_at:
        qs = qs.filter(created_at__gt=state.deleted_at)
    hidden = _hidden_message_ids_for(thread, prof)
    if hidden:
        qs = qs.exclude(pk__in=hidden)
    return qs


def _unread_count_for(thread, prof) -> int:
    qs = _visible_messages_qs(thread, prof).exclude(sender=prof)
    state = _read_state_for(thread, prof)
    if state:
        qs = qs.filter(created_at__gt=state.last_read_at)
    return qs.count()


def _thread_summary(thread, prof) -> dict:
    other = thread.other_participant(prof)
    last = _visible_messages_qs(thread, prof).order_by('-created_at').first()
    return {
        'id': thread.pk,
        'other': _doctor_card(other),
        'last_message': (
            {
                'body': last.body[:140],
                'sender_id': last.sender_id,
                'is_mine': last.sender_id == prof.id,
                'created_at': last.created_at,
            } if last else None
        ),
        'last_message_at': thread.last_message_at,
        'unread_count': _unread_count_for(thread, prof),
    }


# ── Endpoints ─────────────────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminVerified])
def threads(request):
    """Inbox — all my threads sorted newest-activity-first.

    Threads I've soft-deleted (ThreadReadState.deleted_at set) and where no
    new visible messages exist after deleted_at are filtered out. As soon as
    the other party messages again, the thread reappears.
    """
    prof = request.user.professional
    qs = (
        DirectThread.objects
        .filter(Q(participant_a=prof) | Q(participant_b=prof))
        .select_related('participant_a', 'participant_b')
        .order_by('-last_message_at', '-created_at')
    )
    out = []
    for t in qs[:200]:
        summary = _thread_summary(t, prof)
        if summary['last_message'] is None:
            # Either the thread truly has no messages (just-created, never
            # used) OR everything is hidden by my Delete-for-me. In the
            # second case, skip it from the inbox.
            state = _read_state_for(t, prof)
            if state and state.deleted_at and t.messages.exists():
                continue
        out.append(summary)
    return Response(out)


@api_view(['GET'])
@permission_classes([IsAdminVerified])
def unread_count(request):
    """Total unread messages across all my threads — drives the home badge."""
    prof = request.user.professional
    total = 0
    for t in DirectThread.objects.filter(
        Q(participant_a=prof) | Q(participant_b=prof)
    ):
        total += _unread_count_for(t, prof)
    return Response({'unread_count': total})


@api_view(['POST'])
@permission_classes([IsAdminVerified])
def start_thread_with(request, prof_id):
    """Create-or-fetch a thread with the given professional.

    Idempotent — same call always returns the same thread for a pair.
    """
    me = request.user.professional
    if prof_id == me.id:
        return Response({'detail': 'Cannot message yourself.'},
                        status=status.HTTP_400_BAD_REQUEST)
    other = get_object_or_404(MedicalProfessional, pk=prof_id)
    if not other.is_admin_verified:
        return Response({'detail': 'That doctor is not verified yet.'},
                        status=status.HTTP_403_FORBIDDEN)
    if _is_blocked_between(me, other):
        return Response({'detail': 'Messaging is not available between you two.'},
                        status=status.HTTP_403_FORBIDDEN)

    thread, _ = DirectThread.get_or_create_for(me, other)
    return Response(_thread_summary(thread, me), status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([IsAdminVerified])
def thread_detail(request, pk):
    """Paginated messages, oldest-first within the page.

    Pagination params: `before` (ISO datetime) — return at most PAGE_SIZE
    messages whose created_at < before. If omitted, returns the most recent
    page (i.e. tail of the conversation).
    """
    prof = request.user.professional
    thread = get_object_or_404(
        DirectThread.objects.select_related('participant_a', 'participant_b'),
        pk=pk,
    )
    if not thread.has_participant(prof):
        return Response({'detail': 'Not a participant.'},
                        status=status.HTTP_403_FORBIDDEN)

    msgs_qs = _visible_messages_qs(thread, prof)
    before = request.query_params.get('before')
    if before:
        try:
            cutoff = timezone.datetime.fromisoformat(before)
            msgs_qs = msgs_qs.filter(created_at__lt=cutoff)
        except (ValueError, TypeError):
            pass

    # Take the most recent PAGE_SIZE then reverse to chronological for the UI.
    recent = list(msgs_qs.order_by('-created_at')[:PAGE_SIZE])
    recent.reverse()

    return Response({
        'thread': _thread_summary(thread, prof),
        'messages': [
            {
                'id': m.pk,
                'sender_id': m.sender_id,
                'is_mine': m.sender_id == prof.id,
                'body': m.body,
                'created_at': m.created_at,
            }
            for m in recent
        ],
        'has_more': msgs_qs.count() > len(recent),
    })


@api_view(['POST'])
@permission_classes([IsAdminVerified])
def send_message(request, pk):
    me = request.user.professional
    thread = get_object_or_404(DirectThread, pk=pk)
    if not thread.has_participant(me):
        return Response({'detail': 'Not a participant.'},
                        status=status.HTTP_403_FORBIDDEN)

    body = (request.data.get('body') or '').strip()
    if not body:
        return Response({'detail': 'Message body is required.'},
                        status=status.HTTP_400_BAD_REQUEST)
    if len(body) > MAX_BODY_LEN:
        return Response(
            {'detail': f'Message too long ({MAX_BODY_LEN} char max).'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    other = thread.other_participant(me)
    if _is_blocked_between(me, other):
        return Response({'detail': 'Messaging is not available between you two.'},
                        status=status.HTTP_403_FORBIDDEN)

    msg = DirectMessage.objects.create(thread=thread, sender=me, body=body)
    thread.last_message_at = msg.created_at
    thread.save(update_fields=['last_message_at'])

    # FCM push to the other participant
    try:
        tokens = list(
            DeviceToken.objects.filter(user=other.user)
            .values_list('token', flat=True)
        )
        sender_name = me.full_name or 'A colleague'
        preview = body[:120]
        for token in tokens:
            send_push_notification(
                fcm_token=token,
                title=f'💬 {sender_name}',
                body=preview,
                data={
                    'type': 'direct_message',
                    'thread_id': str(thread.pk),
                    'sender_id': str(me.id),
                    'deep_link': f'/messages/{thread.pk}',
                },
                channel_id='default',
            )
    except Exception as e:
        logger.warning(f'[messaging] push failed for msg #{msg.pk}: {e}')

    return Response({
        'id': msg.pk,
        'sender_id': msg.sender_id,
        'is_mine': True,
        'body': msg.body,
        'created_at': msg.created_at,
        'thread_id': thread.pk,
    }, status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([IsAdminVerified])
def mark_read(request, pk):
    me = request.user.professional
    thread = get_object_or_404(DirectThread, pk=pk)
    if not thread.has_participant(me):
        return Response({'detail': 'Not a participant.'},
                        status=status.HTTP_403_FORBIDDEN)
    state, _ = ThreadReadState.objects.get_or_create(thread=thread, professional=me)
    state.last_read_at = timezone.now()
    state.save(update_fields=['last_read_at'])
    return Response({'ok': True})


@api_view(['DELETE'])
@permission_classes([IsAdminVerified])
def delete_thread(request, pk):
    """Soft-delete this thread for the calling professional only.

    Sets `ThreadReadState.deleted_at = now`. New messages from the other
    side after this timestamp will un-hide the thread automatically.
    """
    me = request.user.professional
    thread = get_object_or_404(DirectThread, pk=pk)
    if not thread.has_participant(me):
        return Response({'detail': 'Not a participant.'},
                        status=status.HTTP_403_FORBIDDEN)
    state, _ = ThreadReadState.objects.get_or_create(thread=thread, professional=me)
    state.deleted_at = timezone.now()
    state.last_read_at = timezone.now()
    state.save(update_fields=['deleted_at', 'last_read_at'])
    return Response({'ok': True})


@api_view(['DELETE'])
@permission_classes([IsAdminVerified])
def delete_message(request, pk, msg_id):
    """Soft-delete a single message for the calling professional only.

    Other side still sees it. Idempotent — re-deleting is a no-op.
    """
    me = request.user.professional
    thread = get_object_or_404(DirectThread, pk=pk)
    if not thread.has_participant(me):
        return Response({'detail': 'Not a participant.'},
                        status=status.HTTP_403_FORBIDDEN)
    msg = get_object_or_404(DirectMessage, pk=msg_id, thread=thread)
    DirectMessageHide.objects.get_or_create(message=msg, professional=me)
    return Response({'ok': True})
