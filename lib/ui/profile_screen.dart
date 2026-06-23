import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/own_profile.dart';
import '../providers/ble_providers.dart';

const avatarColors = [
  Color(0xFF378ADD),
  Color(0xFF1D9E75),
  Color(0xFFD85A30),
  Color(0xFFBA7517),
  Color(0xFF534AB7),
  Color(0xFFD4537E),
];

// ASCII 印字可能文字のみ許可（スペース〜チルダ）
final _asciiFormatter =
    FilteringTextInputFormatter.allow(RegExp(r'[\x20-\x7E]'));

String _stripNonAscii(String s) =>
    s.replaceAll(RegExp(r'[^\x20-\x7E]'), '');

class ProfileScreen extends ConsumerStatefulWidget {
  final bool isFirstLaunch;
  const ProfileScreen({super.key, this.isFirstLaunch = false});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _msgCtrl;
  late int _colorIndex;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(appProvider).ownProfile;
    _nameCtrl = TextEditingController(text: profile?.name ?? '');
    _msgCtrl = TextEditingController(text: profile?.message ?? '');
    _colorIndex = profile?.colorIndex ?? 0;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  // IME 経由で日本語が差し込まれた場合もここで弾く
  void _sanitize(TextEditingController ctrl, {bool rebuild = false}) {
    final filtered = _stripNonAscii(ctrl.text);
    if (filtered != ctrl.text) {
      ctrl.value = TextEditingValue(
        text: filtered,
        selection: TextSelection.collapsed(offset: filtered.length),
      );
    }
    if (rebuild) setState(() {});
  }

  Future<void> _save() async {
    _sanitize(_nameCtrl);
    _sanitize(_msgCtrl);
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }
    final existing = ref.read(appProvider).ownProfile;
    await ref.read(appProvider.notifier).saveOwnProfile(
          OwnProfile(
            name: name,
            message: _msgCtrl.text.trim(),
            colorIndex: _colorIndex,
            registeredAt: existing?.registeredAt,
          ),
        );
    if (!widget.isFirstLaunch && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(appProvider).ownProfile;
    final registeredAt = profile?.registeredAt;
    final initial =
        _nameCtrl.text.isNotEmpty ? _nameCtrl.text.characters.first : '?';

    final avatar = CircleAvatar(
      radius: 48,
      backgroundColor: avatarColors[_colorIndex],
      child: Text(
        initial,
        style: const TextStyle(
            fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );

    final body = CustomScrollView(
      slivers: [
        if (!widget.isFirstLaunch)
          const SliverAppBar.large(title: Text('プロフィール'))
        else
          const SliverAppBar(
            title: Text('Profile Setup'),
            automaticallyImplyLeading: false,
            pinned: true,
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 12),
              Center(child: avatar),
              const SizedBox(height: 28),
              TextField(
                controller: _nameCtrl,
                maxLength: 10,
                keyboardType: TextInputType.emailAddress,
                inputFormatters: [_asciiFormatter],
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'English only · max 10 chars',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                onChanged: (_) => _sanitize(_nameCtrl, rebuild: true),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _msgCtrl,
                maxLength: 20,
                keyboardType: TextInputType.emailAddress,
                inputFormatters: [_asciiFormatter],
                decoration: const InputDecoration(
                  labelText: 'Message',
                  hintText: 'English only · URL OK',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.chat_bubble_outline),
                ),
                onChanged: (_) => _sanitize(_msgCtrl),
              ),
              const SizedBox(height: 24),
              Text('Avatar Color',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(avatarColors.length, (i) {
                  final selected = i == _colorIndex;
                  return GestureDetector(
                    onTap: () => setState(() => _colorIndex = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: avatarColors[i],
                        border: selected
                            ? Border.all(
                                color:
                                    Theme.of(context).colorScheme.onSurface,
                                width: 3)
                            : null,
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                    color: avatarColors[i].withOpacity(0.5),
                                    blurRadius: 8)
                              ]
                            : null,
                      ),
                      child: selected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 22)
                          : null,
                    ),
                  );
                }),
              ),
              if (registeredAt != null) ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 8),
                    Text('登録日',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline)),
                    const Spacer(),
                    Text(
                      '${registeredAt.year}/${registeredAt.month.toString().padLeft(2, '0')}/${registeredAt.day.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 36),
              FilledButton.icon(
                onPressed: _save,
                icon: Icon(widget.isFirstLaunch
                    ? Icons.arrow_forward
                    : Icons.check),
                label: Text(widget.isFirstLaunch ? 'Start' : '保存'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
              ),
              if (widget.isFirstLaunch) ...[
                const SizedBox(height: 12),
                Text(
                  'Your name and message are shared with nearby people.\nEnglish only. Anonymous OK.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline),
                  textAlign: TextAlign.center,
                ),
              ],
            ]),
          ),
        ),
      ],
    );

    return widget.isFirstLaunch ? Scaffold(body: body) : body;
  }
}
