"""Per-category recipient filtering for SOS.

Rules (locked 2026-05-02):

  urgent_clinical   → only doctors in the SAME specialty cluster as the sender
                       (e.g. dentist → dental cluster + anaesthesiologist).
                       Reuses consultants.specialty_map for the cluster
                       definition so behaviour stays consistent with the
                       consultant search.
  medical_emergency → all medical (non-dental) doctors. Dentists are excluded
                       — they cannot help with a medical emergency.
  legal_issue       → no filter (any verified doctor nearby).
  clinic_threat     → no filter (any verified doctor nearby).

Applied in two places:
  • GET /sos/nearby-doctors/?category=… → drives the recipient picker UI so
    the sender only ever sees valid candidates.
  • POST /sos/send/                      → defense in depth, in case a stale
    client uploads a `recipient_ids` list that bypassed the picker.
"""

from consultants.specialty_map import (
    ALL,
    CONSULTANT_SEARCH_MAP,
    DENTAL_CLUSTER,
)


def _sos_cluster_for(specialty: str):
    """Same-specialty cluster for urgent_clinical SOS.

    Reuses the consultant search map for the cluster definition, but
    deliberately ignores the `hospital_owner` ALL bypass — for SOS we want
    a dentist (even one who also owns a hospital) to alert dentists, not
    everyone. Returns the `ALL` sentinel only when the specialty itself
    has no cluster (e.g. `other`, `emergency_medicine`).
    """
    return CONSULTANT_SEARCH_MAP.get(specialty, ALL)


def filtered_clinics_for_sos(category: str, sender_prof, clinics):
    """Filter `clinics` to those whose owner is allowed to receive this SOS.

    `clinics` is a list of `Clinic` rows from `find_nearby_clinics`. Returns a
    new list (preserves input ordering) — never mutates.

    `sender_prof` is the `MedicalProfessional` of the SOS sender. Used only
    for `urgent_clinical` to derive the same-cluster filter.

    Unknown / future categories fall through with no filter — fail open so a
    rule typo never silently swallows a valid SOS.
    """
    if category in ('legal_issue', 'clinic_threat'):
        return list(clinics)

    if category == 'medical_emergency':
        return [c for c in clinics if c.owner.specialization not in DENTAL_CLUSTER]

    if category == 'urgent_clinical':
        allowed = _sos_cluster_for(sender_prof.specialization)
        if allowed == ALL:
            return list(clinics)
        return [c for c in clinics if c.owner.specialization in allowed]

    return list(clinics)


def category_audience_label(category: str, sender_prof) -> str:
    """One-line human label for the recipient picker header.

    Examples:
      urgent_clinical   → "Showing dentists near you"
      medical_emergency → "Showing medical doctors (dentists excluded)"
      legal_issue       → "Showing all doctors near you"
      clinic_threat     → "Showing all doctors near you"
    """
    if category == 'medical_emergency':
        return 'Showing medical doctors near you (dentists excluded)'
    if category == 'urgent_clinical':
        allowed = _sos_cluster_for(sender_prof.specialization)
        if allowed == ALL:
            return 'Showing all doctors near you'
        # Friendly cluster name when sender is dental
        if sender_prof.specialization in DENTAL_CLUSTER:
            return 'Showing dentists near you (incl. dental specialists)'
        return 'Showing doctors in your specialty near you'
    return 'Showing all doctors near you'
