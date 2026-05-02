"""Specialty filter for the live-consultant search.

Maps a searcher's specialization to the set of consultant specializations they
can see. `hospital_owner` role bypasses this filter entirely (sees everyone).

Strawman approved 2026-05-02 for initial testing — refine later with usage data.
Symmetric except `anaesthesiologist` and `emergency_medicine` (both see all).
"""

DENTAL_CLUSTER = {
    'dentist', 'oral_surgeon', 'endodontist', 'orthodontist',
    'periodontist', 'prosthodontist', 'pedodontist',
}

ALL_MEDICAL_NON_DENTAL = {
    'general_physician', 'cardiologist', 'dermatologist', 'gynaecologist',
    'orthopaedic', 'paediatrician', 'ent_specialist', 'physiotherapist',
    'neurologist', 'psychiatrist', 'ophthalmologist', 'urologist',
    'gastroenterologist', 'pulmonologist', 'endocrinologist', 'oncologist',
    'nephrologist', 'rheumatologist', 'radiologist', 'pathologist',
    'anaesthesiologist', 'general_surgeon', 'plastic_surgeon', 'neurosurgeon',
    'hematologist', 'infectious_disease', 'geriatric', 'emergency_medicine',
}

# Sentinel — searcher gets to see every consultant regardless of specialty.
ALL = '__ALL__'

CONSULTANT_SEARCH_MAP = {
    'dentist': DENTAL_CLUSTER | {'anaesthesiologist'},
    'oral_surgeon': DENTAL_CLUSTER | {'anaesthesiologist'},
    'endodontist': DENTAL_CLUSTER | {'anaesthesiologist'},
    'orthodontist': DENTAL_CLUSTER | {'anaesthesiologist'},
    'periodontist': DENTAL_CLUSTER | {'anaesthesiologist'},
    'prosthodontist': DENTAL_CLUSTER | {'anaesthesiologist'},
    'pedodontist': DENTAL_CLUSTER | {'paediatrician', 'anaesthesiologist'},

    'general_physician': ALL_MEDICAL_NON_DENTAL,
    'paediatrician': {
        'paediatrician', 'general_physician', 'anaesthesiologist',
        'ent_specialist', 'dermatologist', 'neurologist',
    },
    'cardiologist': {'cardiologist', 'anaesthesiologist'},
    'dermatologist': {'dermatologist', 'plastic_surgeon'},
    'gynaecologist': {'gynaecologist', 'paediatrician', 'anaesthesiologist'},
    'orthopaedic': {
        'orthopaedic', 'physiotherapist', 'anaesthesiologist', 'general_surgeon',
    },
    'ent_specialist': {'ent_specialist', 'anaesthesiologist'},
    'physiotherapist': {'physiotherapist', 'orthopaedic'},
    'neurologist': {'neurologist', 'neurosurgeon', 'psychiatrist'},
    'psychiatrist': {'psychiatrist', 'neurologist'},
    'ophthalmologist': {'ophthalmologist', 'anaesthesiologist'},
    'urologist': {'urologist', 'anaesthesiologist', 'general_surgeon'},
    'gastroenterologist': {'gastroenterologist', 'general_surgeon'},
    'pulmonologist': {'pulmonologist', 'cardiologist'},
    'endocrinologist': {'endocrinologist', 'general_physician'},
    'oncologist': {
        'oncologist', 'general_surgeon', 'radiologist', 'pathologist', 'anaesthesiologist',
    },
    'nephrologist': {'nephrologist', 'urologist'},
    'rheumatologist': {'rheumatologist', 'orthopaedic'},
    'radiologist': {'radiologist'},
    'pathologist': {'pathologist'},
    'anaesthesiologist': ALL,
    'general_surgeon': {
        'general_surgeon', 'plastic_surgeon', 'neurosurgeon', 'orthopaedic',
        'oral_surgeon', 'anaesthesiologist', 'radiologist',
    },
    'plastic_surgeon': {
        'plastic_surgeon', 'general_surgeon', 'anaesthesiologist', 'dermatologist',
    },
    'neurosurgeon': {'neurosurgeon', 'neurologist', 'anaesthesiologist'},
    'hematologist': {'hematologist', 'oncologist', 'pathologist'},
    'infectious_disease': {'infectious_disease', 'general_physician'},
    'geriatric': {'geriatric', 'general_physician', 'cardiologist'},
    'emergency_medicine': ALL,
    'other': ALL,
}


def searchable_specialties(searcher_specialty: str, searcher_roles: list) -> set | str:
    """Return the set of consultant specialties this searcher can see.

    Returns `ALL` (a sentinel string) if no filter should be applied.
    """
    roles = set(searcher_roles or [])
    if 'hospital_owner' in roles:
        return ALL
    return CONSULTANT_SEARCH_MAP.get(searcher_specialty, ALL)
