import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/bike_catalogue.dart';
import '../../models/bike_choice.dart';
import '../../models/bike_profile.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../safety_briefing_screen.dart';
import 'make_chips.dart';
import 'model_change_dialog.dart';
import 'model_list.dart';
import 'other_bike_form.dart';

/// Which bike: make, then model from the bundled catalogue, or "Other".
class BikeSetupScreen extends StatefulWidget {
  const BikeSetupScreen({super.key, this.editing = false});

  /// Editing an existing bike from Home (pops back) rather than first-run
  /// onboarding (continues to the init ride briefing).
  final bool editing;

  static String? validateTopSpeed(String? value) =>
      TopSpeedField.validate(value);

  @override
  State<BikeSetupScreen> createState() => _BikeSetupScreenState();
}

class _BikeSetupScreenState extends State<BikeSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _revealKey = GlobalKey();
  final _selectedKey = GlobalKey();
  final _errorKey = GlobalKey();
  final _topSpeed = TextEditingController();
  final _otherMake = TextEditingController();
  final _otherModel = TextEditingController();
  final _otherYear = TextEditingController();
  final _otherTopSpeed = TextEditingController();

  late final BikeCatalogue _catalogue = context.read<AppState>().catalogue;
  late final BikeProfile? _bike = context.read<AppState>().bike;
  String? _make;
  CatalogueModel? _model;
  bool _allMakes = false;
  bool _other = false;
  String? _pickError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final bike = _bike;
    if (bike == null) return;
    final id = bike.catalogueModelId;
    final known = id == null ? null : _catalogue.byId(id);
    if (known != null) {
      _make = known.make;
      _allMakes = _hiddenWhenCollapsed(known.make);
      _selectModel(known);
      _afterFrame(() => _reveal(_selectedKey, alignment: 0.4));
    } else {
      _other = true;
      _prefillOther(bike);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _topSpeed,
      _otherMake,
      _otherModel,
      _otherYear,
      _otherTopSpeed,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _hiddenWhenCollapsed(String make) =>
      _catalogue.makes.indexOf(make) >= MakeChips.collapsedCount;

  /// An Other or legacy bike (or one no longer in the catalogue). A legacy
  /// bike's text that starts with a known make is split into make and model.
  void _prefillOther(BikeProfile bike) {
    var make = bike.otherMake ?? '';
    var model = bike.isOther ? (bike.otherModel ?? bike.model) : bike.model;
    if (make.isEmpty) {
      for (final m in _catalogue.makes) {
        if (!model.toLowerCase().startsWith('${m.toLowerCase()} ')) continue;
        final rest = model.substring(m.length + 1).trim();
        if (rest.isEmpty) continue;
        make = model.substring(0, m.length);
        model = rest;
        break;
      }
    }
    _otherMake.text = make;
    _otherModel.text = model;
    _otherYear.text = bike.otherYear?.toString() ?? '';
    _otherTopSpeed.text = TopSpeedField.format(bike.ratedTopSpeedKmh);
  }

  /// Picks [m]; the speed field is prefilled only with what the rider
  /// typed for this same model before.
  void _selectModel(CatalogueModel m) {
    _model = m;
    _pickError = null;
    final bike = _bike;
    _topSpeed.text =
        bike != null &&
            bike.catalogueModelId == m.id &&
            bike.topSpeedSource != TopSpeedSource.catalogue
        ? TopSpeedField.format(bike.ratedTopSpeedKmh)
        : '';
  }

  void _onMake(String make) {
    setState(() {
      _make = make;
      _pickError = null;
      if (_model?.make != make) {
        _model = null;
        _topSpeed.clear();
      }
    });
    _afterFrame(() => _reveal(_revealKey));
  }

  void _onModel(CatalogueModel m) {
    setState(() => _selectModel(m));
    if (m.topSpeedKmh == null) _afterFrame(() => _reveal(_selectedKey));
  }

  void _setOther(bool other) {
    FocusScope.of(context).unfocus();
    setState(() {
      _other = other;
      _pickError = null;
    });
  }

  void _afterFrame(VoidCallback f) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) f();
      });

  /// Scrolls [key] into view: by default only as far as needed to show it.
  void _reveal(GlobalKey key, {double? alignment}) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: alignment ?? 1,
      alignmentPolicy: alignment == null
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.explicit,
    );
  }

  /// What the page describes, or null (with the reason shown) if incomplete.
  BikeChoice? _choice() {
    if (_other) {
      if (!_formKey.currentState!.validate()) return null;
      return OtherChoice(
        make: _otherMake.text,
        model: _otherModel.text,
        year: int.tryParse(_otherYear.text.trim()),
        topSpeedKmh: double.parse(_otherTopSpeed.text.trim()),
      );
    }
    final m = _model;
    if (m == null) {
      setState(
        () => _pickError = _make == null
            ? 'Choose your make'
            : 'Choose your model',
      );
      _afterFrame(() => _reveal(_errorKey, alignment: 0.3));
      return null;
    }
    if (!_formKey.currentState!.validate()) {
      _reveal(_selectedKey, alignment: 0.3);
      return null;
    }
    return CatalogueChoice(
      model: m,
      riderTopSpeedKmh: m.topSpeedKmh == null
          ? double.parse(_topSpeed.text.trim())
          : null,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final choice = _choice();
    if (choice == null) return;
    final app = context.read<AppState>();
    final existing = app.bike;
    var differentBike = false;
    if (existing != null &&
        app.calibration != null &&
        modelChanged(existing, choice)) {
      final answer = await askModelChange(context);
      if (answer == null || !mounted) return;
      differentBike = answer == ModelChange.differentBike;
    }
    setState(() => _saving = true);
    try {
      await app.saveBike(choice, differentBike: differentBike);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    final nav = Navigator.of(context);
    final briefing = MaterialPageRoute<void>(
      builder: (_) => const SafetyBriefingScreen(),
    );
    if (differentBike) {
      // A new bike needs its own init ride before anything else.
      nav.pushAndRemoveUntil(briefing, (_) => false);
    } else if (widget.editing) {
      nav.pop();
    } else {
      nav.pushReplacement(briefing);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_other,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _other) _setOther(false);
      },
      child: Scaffold(
        appBar: widget.editing || _other
            ? AppBar(
                title: widget.editing ? const Text('EDIT BIKE') : null,
                leading: _other
                    ? BackButton(onPressed: () => _setOther(false))
                    : null,
              )
            : null,
        body: GradientBackground(
          child: SafeArea(
            top: !(widget.editing || _other),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    // A fresh scroll position for each mode.
                    key: ValueKey(_other),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _other ? _otherPage() : _pickerPage(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: PrimaryButton(
                      key: const Key('save-bike'),
                      label: widget.editing ? 'SAVE' : 'CONTINUE',
                      icon: widget.editing
                          ? Icons.check
                          : Icons.arrow_forward_rounded,
                      busy: _saving,
                      onPressed: _save,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _pickerPage() {
    final make = _make;
    final model = _model;
    return [
      if (!widget.editing) ...[
        const _Logo(),
        const SizedBox(height: 20),
        Text(
          'SET UP YOUR BIKE',
          textAlign: TextAlign.center,
          style: AppText.display(20),
        ),
        const SizedBox(height: 8),
        Text(
          'RideGuard calibrates to your motorcycle and the way your phone '
          'is mounted.',
          textAlign: TextAlign.center,
          style: AppText.body(16, color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
      ],
      Text('MAKE', style: AppText.label(13)),
      const SizedBox(height: 10),
      MakeChips(
        makes: _catalogue.makes,
        selected: make,
        expanded: _allMakes,
        onSelected: _onMake,
        onExpand: () => setState(() => _allMakes = true),
      ),
      if (make == null) ..._error(),
      if (make != null) ...[
        const SizedBox(height: 24),
        Text('MODEL', style: AppText.label(13)),
        ..._error(),
        const SizedBox(height: 10),
        ModelList(
          models: _catalogue.modelsFor(make),
          selected: model,
          onSelected: _onModel,
          selectedKey: _selectedKey,
          revealKey: _revealKey,
          belowSelected: model != null && model.topSpeedKmh == null
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TopSpeedField(controller: _topSpeed, onSubmit: _save),
                )
              : null,
        ),
      ],
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          key: const Key('other-bike'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.amber,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onPressed: () => _setOther(true),
          child: Text(
            "My bike isn't listed → Other",
            style: AppText.body(
              16,
              color: AppColors.amber,
              weight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _error() => [
    if (_pickError != null)
      Padding(
        key: _errorKey,
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _pickError!,
          style: AppText.body(
            15,
            color: AppColors.red,
            weight: FontWeight.w700,
          ),
        ),
      ),
  ];

  List<Widget> _otherPage() => [
    Text('OTHER BIKE', textAlign: TextAlign.center, style: AppText.display(20)),
    const SizedBox(height: 8),
    Text(
      "Tell us what you ride. We'll add it to the list.",
      textAlign: TextAlign.center,
      style: AppText.body(16, color: AppColors.textMuted),
    ),
    const SizedBox(height: 24),
    OtherBikeForm(
      make: _otherMake,
      model: _otherModel,
      year: _otherYear,
      topSpeed: _otherTopSpeed,
      onSubmit: _save,
    ),
  ];
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.red, Color(0xFFFF6B6B)],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.4),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Icon(Icons.two_wheeler, size: 38, color: Colors.white),
        ),
        const SizedBox(height: 16),
        Text(
          'RIDEGUARD',
          style: AppText.display(28).copyWith(letterSpacing: 8),
        ),
      ],
    );
  }
}
