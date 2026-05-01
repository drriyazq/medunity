import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api/client.dart';
import '../../data/local/hive_setup.dart';
import '../../state/auth_provider.dart';
import '../../theme.dart';

// ── India choice data (mirrors backend models.py) ────────────────────────────

const _specializations = [
  ('general_physician', 'General Physician'), ('dentist', 'Dentist'),
  ('oral_surgeon', 'Oral Surgeon'), ('endodontist', 'Endodontist'),
  ('orthodontist', 'Orthodontist'), ('periodontist', 'Periodontist'),
  ('prosthodontist', 'Prosthodontist'), ('pedodontist', 'Pedodontist'),
  ('cardiologist', 'Cardiologist'), ('dermatologist', 'Dermatologist'),
  ('gynaecologist', 'Gynaecologist'), ('orthopaedic', 'Orthopaedic Surgeon'),
  ('paediatrician', 'Paediatrician'), ('ent_specialist', 'ENT Specialist'),
  ('physiotherapist', 'Physiotherapist'), ('neurologist', 'Neurologist'),
  ('psychiatrist', 'Psychiatrist'), ('ophthalmologist', 'Ophthalmologist'),
  ('anaesthesiologist', 'Anaesthesiologist'), ('general_surgeon', 'General Surgeon'),
  ('emergency_medicine', 'Emergency Medicine'), ('other', 'Other'),
];

const _councils = [
  ('nmc', 'NMC — National Medical Commission'),
  ('dci', 'DCI — Dental Council of India'),
  ('inc', 'INC — Indian Nursing Council'),
  ('mci_legacy', 'MCI (legacy)'),
  ('maharashtra_mc', 'Maharashtra Medical Council'),
  ('karnataka_mc', 'Karnataka Medical Council'),
  ('tn_mc', 'Tamil Nadu Medical Council'),
  ('delhi_mc', 'Delhi Medical Council'),
  ('gujarat_mc', 'Gujarat Medical Council'),
  ('kerala_mc', 'Kerala Medical Council'),
  ('up_mc', 'Uttar Pradesh Medical Council'),
  ('other_council', 'Other State Council'),
];

const _roles = [
  ('clinic_owner', 'Clinic Owner / Primary Physician'),
  ('visiting_consultant', 'Visiting Consultant / Specialist'),
];

const _states = [
  'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh',
  'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka',
  'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya',
  'Mizoram', 'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim',
  'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand',
  'West Bengal', 'Delhi', 'Jammu and Kashmir', 'Ladakh', 'Chandigarh',
];

const _draftKey = 'profile_setup_draft';


class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _pageCtrl = PageController();
  int _step = 0;
  bool _submitting = false;
  String? _error;

  // Step 1
  final _nameCtrl = TextEditingController();
  String _role = _roles[0].$1;
  String _specialization = _specializations[0].$1;
  final _yearsCtrl = TextEditingController();

  // Step 2
  String _council = _councils[0].$1;
  final _licenseCtrl = TextEditingController();
  File? _licenseDoc;
  File? _degreeDoc;

  // Step 3 — clinic
  final _clinicNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  String _clinicState = _states[0];
  final _pincodeCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _restoreDraft();
    if (_phoneCtrl.text.isEmpty) {
      final verified = HiveSetup.sessionBox.get('verified_phone') as String?;
      if (verified != null) _phoneCtrl.text = verified;
    }
  }

  @override
  void dispose() {
    _saveDraft();
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _yearsCtrl.dispose();
    _licenseCtrl.dispose();
    _clinicNameCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _pincodeCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _restoreDraft() {
    final raw = HiveSetup.sessionBox.get(_draftKey);
    if (raw is! Map) return;
    final d = Map<String, dynamic>.from(raw);
    _nameCtrl.text = d['name'] ?? '';
    _role = d['role'] ?? _roles[0].$1;
    _specialization = d['specialization'] ?? _specializations[0].$1;
    _yearsCtrl.text = d['years'] ?? '';
    _council = d['council'] ?? _councils[0].$1;
    _licenseCtrl.text = d['license'] ?? '';
    _clinicNameCtrl.text = d['clinicName'] ?? '';
    _addressCtrl.text = d['address'] ?? '';
    _cityCtrl.text = d['city'] ?? '';
    _clinicState = d['clinicState'] ?? _states[0];
    _pincodeCtrl.text = d['pincode'] ?? '';
    _phoneCtrl.text = d['phone'] ?? '';
    _step = (d['step'] as int?) ?? 0;
    final lic = d['licenseDocPath'] as String?;
    final deg = d['degreeDocPath'] as String?;
    if (lic != null && File(lic).existsSync()) _licenseDoc = File(lic);
    if (deg != null && File(deg).existsSync()) _degreeDoc = File(deg);
    if (_step > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pageCtrl.jumpToPage(_step);
      });
    }
  }

  void _saveDraft() {
    HiveSetup.sessionBox.put(_draftKey, {
      'step': _step,
      'name': _nameCtrl.text,
      'role': _role,
      'specialization': _specialization,
      'years': _yearsCtrl.text,
      'council': _council,
      'license': _licenseCtrl.text,
      'clinicName': _clinicNameCtrl.text,
      'address': _addressCtrl.text,
      'city': _cityCtrl.text,
      'clinicState': _clinicState,
      'pincode': _pincodeCtrl.text,
      'phone': _phoneCtrl.text,
      'licenseDocPath': _licenseDoc?.path,
      'degreeDocPath': _degreeDoc?.path,
    });
  }

  Future<void> _pickFile(void Function(File) setter) async {
    final xFile = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xFile != null) {
      setState(() => setter(File(xFile.path)));
      _saveDraft();
    }
  }

  void _next() {
    _saveDraft();
    if (_step < 2) {
      setState(() => _step++);
      _pageCtrl.animateToPage(_step, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step == 0) return;
    setState(() {
      _step--;
      _error = null;
    });
    _pageCtrl.animateToPage(_step, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    _saveDraft();
  }

  Future<void> _submit() async {
    setState(() { _submitting = true; _error = null; });
    final dio = ref.read(dioProvider);
    try {
      final form = FormData.fromMap({
        'full_name': _nameCtrl.text.trim(),
        'role': _role,
        'specialization': _specialization,
        'years_experience': _yearsCtrl.text.trim(),
        'medical_council': _council,
        'license_number': _licenseCtrl.text.trim(),
        'clinic_name': _clinicNameCtrl.text.trim(),
        'clinic_address': _addressCtrl.text.trim(),
        'clinic_city': _cityCtrl.text.trim(),
        'clinic_state': _clinicState,
        'clinic_pincode': _pincodeCtrl.text.trim(),
        'clinic_phone': _phoneCtrl.text.trim(),
        if (_licenseDoc != null)
          'license_doc': await MultipartFile.fromFile(_licenseDoc!.path, filename: 'license.jpg'),
        if (_degreeDoc != null)
          'degree_doc': await MultipartFile.fromFile(_degreeDoc!.path, filename: 'degree.jpg'),
      });
      await dio.post('/auth/profile/', data: form,
          options: Options(contentType: 'multipart/form-data'));
      await HiveSetup.sessionBox.delete(_draftKey);
      await ref.read(authProvider.notifier).onProfileCreated();
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['detail'] ?? 'Submission failed. Please try again.';
        _submitting = false;
      });
    } catch (_) {
      setState(() { _error = 'Unexpected error. Please try again.'; _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _step > 0
              ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back)
              : null,
          automaticallyImplyLeading: _step == 0,
          title: Text(
            'Step ${_step + 1} of 3',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
        ),
        body: Column(
          children: [
            LinearProgressIndicator(value: (_step + 1) / 3, color: MedUnityColors.primary),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [_step1(), _step2(), _step3()],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                child: Text(_error!, style: const TextStyle(color: MedUnityColors.sos)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Row(
                children: [
                  if (_step > 0) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting ? null : _back,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: _step > 0 ? 2 : 1,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _next,
                      child: _submitting
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_step < 2 ? 'Next' : 'Submit for Verification'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step1() => _FormPage(children: [
    _label('Full name (as on license)'),
    TextField(controller: _nameCtrl, decoration: const InputDecoration(hintText: 'Dr. Firstname Lastname')),
    const SizedBox(height: 20),
    _label('Role'),
    DropdownButtonFormField<String>(
      value: _role,
      isExpanded: true,
      items: _roles.map((r) => DropdownMenuItem(value: r.$1, child: Text(r.$2, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) { setState(() => _role = v!); _saveDraft(); },
      decoration: const InputDecoration(),
    ),
    const SizedBox(height: 20),
    _label('Specialization'),
    DropdownButtonFormField<String>(
      value: _specialization,
      isExpanded: true,
      items: _specializations.map((s) => DropdownMenuItem(value: s.$1, child: Text(s.$2, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) { setState(() => _specialization = v!); _saveDraft(); },
      decoration: const InputDecoration(),
    ),
    const SizedBox(height: 20),
    _label('Years of experience'),
    TextField(controller: _yearsCtrl, keyboardType: TextInputType.number,
        decoration: const InputDecoration(hintText: 'e.g. 8')),
  ]);

  Widget _step2() => _FormPage(children: [
    _label('Medical Council'),
    DropdownButtonFormField<String>(
      value: _council,
      isExpanded: true,
      items: _councils.map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) { setState(() => _council = v!); _saveDraft(); },
      decoration: const InputDecoration(),
    ),
    const SizedBox(height: 20),
    _label('Registration / License Number'),
    TextField(controller: _licenseCtrl, decoration: const InputDecoration(hintText: 'e.g. MH/12345/2015')),
    const SizedBox(height: 20),
    _label('License document (photo/scan)'),
    _PickerRow(
      label: _licenseDoc == null ? 'Tap to upload' : '✓ ${_licenseDoc!.path.split('/').last}',
      onTap: () => _pickFile((f) => _licenseDoc = f),
    ),
    const SizedBox(height: 12),
    _label('Degree certificate (MBBS / BDS / MD etc.)'),
    _PickerRow(
      label: _degreeDoc == null ? 'Tap to upload' : '✓ ${_degreeDoc!.path.split('/').last}',
      onTap: () => _pickFile((f) => _degreeDoc = f),
    ),
  ]);

  Widget _step3() => _FormPage(children: [
    _label('Clinic / Hospital name'),
    TextField(controller: _clinicNameCtrl, decoration: const InputDecoration(hintText: 'e.g. Tru Smile Dental Clinic')),
    const SizedBox(height: 20),
    _label('Address'),
    TextField(controller: _addressCtrl, maxLines: 2, decoration: const InputDecoration(hintText: 'Street, area, landmark')),
    const SizedBox(height: 20),
    Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label('City'),
        TextField(controller: _cityCtrl, decoration: const InputDecoration(hintText: 'City')),
      ])),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label('Pincode'),
        TextField(controller: _pincodeCtrl, keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '400001')),
      ])),
    ]),
    const SizedBox(height: 20),
    _label('State'),
    DropdownButtonFormField<String>(
      value: _clinicState,
      isExpanded: true,
      items: _states.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) { setState(() => _clinicState = v!); _saveDraft(); },
      decoration: const InputDecoration(),
    ),
    const SizedBox(height: 20),
    _label('Clinic phone number'),
    TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone,
        decoration: const InputDecoration(hintText: '+919876543210')),
  ]);

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
  );
}

class _FormPage extends StatelessWidget {
  final List<Widget> children;
  const _FormPage({required this.children});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

class _PickerRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PickerRow({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: MedUnityColors.border),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      child: Row(children: [
        const Icon(Icons.upload_file, color: MedUnityColors.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(color: MedUnityColors.textSecondary), overflow: TextOverflow.ellipsis)),
      ]),
    ),
  );
}
