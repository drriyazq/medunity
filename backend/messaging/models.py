from django.db import models
from django.utils import timezone

from accounts.models import MedicalProfessional


class DirectThread(models.Model):
    """Single 1:1 conversation between two MedicalProfessionals.

    Pair is canonicalised so `participant_a.id < participant_b.id` — the
    unique-together then guarantees exactly one thread per pair regardless
    of who started it. Use `get_or_create_for(p1, p2)` from view code; never
    instantiate directly.
    """
    participant_a = models.ForeignKey(
        MedicalProfessional,
        on_delete=models.CASCADE,
        related_name='threads_as_a',
    )
    participant_b = models.ForeignKey(
        MedicalProfessional,
        on_delete=models.CASCADE,
        related_name='threads_as_b',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    last_message_at = models.DateTimeField(null=True, blank=True, db_index=True)

    class Meta:
        unique_together = ('participant_a', 'participant_b')
        ordering = ['-last_message_at', '-created_at']

    def __str__(self):
        return f'Thread #{self.pk}: {self.participant_a_id} ↔ {self.participant_b_id}'

    @classmethod
    def get_or_create_for(cls, p1: MedicalProfessional, p2: MedicalProfessional):
        if p1.id == p2.id:
            raise ValueError('Cannot create thread with self')
        a, b = (p1, p2) if p1.id < p2.id else (p2, p1)
        thread, created = cls.objects.get_or_create(participant_a=a, participant_b=b)
        return thread, created

    def other_participant(self, prof: MedicalProfessional) -> MedicalProfessional:
        if prof.id == self.participant_a_id:
            return self.participant_b
        if prof.id == self.participant_b_id:
            return self.participant_a
        raise ValueError(f'Professional {prof.id} is not in thread {self.pk}')

    def has_participant(self, prof: MedicalProfessional) -> bool:
        return prof.id in (self.participant_a_id, self.participant_b_id)


class DirectMessage(models.Model):
    thread = models.ForeignKey(
        DirectThread, on_delete=models.CASCADE, related_name='messages',
    )
    sender = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='messages_sent',
    )
    body = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ['created_at']
        indexes = [
            models.Index(fields=['thread', 'created_at']),
        ]

    def __str__(self):
        return f'Msg #{self.pk} in thread {self.thread_id} from {self.sender_id}'


class ThreadReadState(models.Model):
    """Per-participant last-read marker for unread-count computation.

    Created on first read. `last_read_at` is updated on POST /read/.
    Unread = thread.messages.filter(created_at__gt=last_read_at).exclude(sender=me).count().
    """
    thread = models.ForeignKey(
        DirectThread, on_delete=models.CASCADE, related_name='read_states',
    )
    professional = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='thread_read_states',
    )
    last_read_at = models.DateTimeField(default=timezone.now)

    class Meta:
        unique_together = ('thread', 'professional')

    def __str__(self):
        return f'Read state: prof {self.professional_id} on thread {self.thread_id}'
