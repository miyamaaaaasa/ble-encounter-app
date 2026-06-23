import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/own_profile.dart';
import '../models/template_message.dart';
import '../providers/ble_providers.dart';
import 'encounter_helpers.dart';

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
  late int _colorIndex;
  late TemplateMessage _template;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(appProvider).ownProfile;
    _nameCtrl = TextEditingController(text: profile?.name ?? '');
    _colorIndex = profile?.colorIndex ?? 0;
    _template = profile?.template ?? const TemplateMessage();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _sanitizeName() {
    final filtered = _stripNonAscii(_nameCtrl.text);
    if (filtered != _nameCtrl.text) {
      _nameCtrl.value = TextEditingValue(
        text: filtered,
        selection: TextSelection.collapsed(offset: filtered.length),
      );
    }
    setState(() {});
  }

  Future<void> _save() async {
    _sanitizeName();
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
            colorIndex: _colorIndex,
            template: _template,
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

    // hobbyDetail のアイテム（カテゴリ変更時に連動）
    final catIdx     = _template.hobbyCategory.clamp(0, TemplateMessage.hobbyDetails.length - 1);
    final detailItems = TemplateMessage.hobbyDetails[catIdx];
    final safeDetail  = _template.hobbyDetail == -1
        ? -1
        : _template.hobbyDetail.clamp(0, detailItems.length - 1);

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

              // ─── 名前 ─────────────────────────────────────────────
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
                onChanged: (_) => _sanitizeName(),
              ),
              const SizedBox(height: 20),

              // ─── 定型文設定 ──────────────────────────────────────
              Text('ひとこと設定',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 12),

              // 状態
              DropdownButtonFormField<int>(
                value: _template.statusIndex,
                decoration: const InputDecoration(
                  labelText: '状態（任意）',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.emoji_emotions_outlined),
                ),
                items: [
                  const DropdownMenuItem(value: -1, child: Text('未回答')),
                  ...TemplateMessage.statusList
                      .asMap()
                      .entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value))),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _template = _template.copyWith(statusIndex: v));
                },
              ),
              const SizedBox(height: 12),

              // 趣味カテゴリ
              DropdownButtonFormField<int>(
                value: _template.hobbyCategory,
                decoration: const InputDecoration(
                  labelText: '趣味カテゴリ（任意）',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.interests_outlined),
                ),
                items: [
                  const DropdownMenuItem(value: -1, child: Text('未回答')),
                  ...TemplateMessage.hobbyCategories
                      .asMap()
                      .entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value))),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _template = _template.copyWith(
                      hobbyCategory: v,
                      hobbyDetail: v == -1 ? -1 : 0));
                },
              ),
              const SizedBox(height: 12),

              // 趣味詳細（カテゴリ連動）
              if (_template.hobbyCategory != -1)
                DropdownButtonFormField<int>(
                  key: ValueKey(_template.hobbyCategory),
                  value: safeDetail,
                  decoration: const InputDecoration(
                    labelText: '趣味詳細（任意）',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.tag_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(value: -1, child: Text('未回答')),
                    ...detailItems
                        .asMap()
                        .entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value))),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _template = _template.copyWith(hobbyDetail: v));
                  },
                ),
              if (_template.hobbyCategory != -1) const SizedBox(height: 12),

              // 締めの一言
              DropdownButtonFormField<int>(
                value: _template.phraseIndex,
                decoration: const InputDecoration(
                  labelText: '締めの一言（任意）',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.chat_bubble_outline),
                ),
                items: [
                  const DropdownMenuItem(value: -1, child: Text('未回答')),
                  ...TemplateMessage.phraseList
                      .asMap()
                      .entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value))),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _template = _template.copyWith(phraseIndex: v));
                },
              ),
              const SizedBox(height: 12),

              // プレビュー
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'プレビュー',
                      style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.outline),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_template.statusText}  ·  ${_template.hobbyCategoryText}(${_template.hobbyDetailText})  ·  ${_template.phraseText}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ─── アバターカラー ──────────────────────────────────
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface,
                                width: 3)
                            : null,
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                    color:
                                        avatarColors[i].withOpacity(0.5),
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
                            color:
                                Theme.of(context).colorScheme.outline)),
                    const Spacer(),
                    Text(
                      fmtDate(registeredAt),
                      style:
                          const TextStyle(fontWeight: FontWeight.w500),
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
                label:
                    Text(widget.isFirstLaunch ? 'Start' : '保存'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
              ),
              if (widget.isFirstLaunch) ...[
                const SizedBox(height: 12),
                Text(
                  'Your name and template message are shared with nearby people.\nEnglish name only. Anonymous OK.',
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
