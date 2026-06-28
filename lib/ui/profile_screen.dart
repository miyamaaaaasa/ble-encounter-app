import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/own_profile.dart';
import '../models/template_message.dart';
import '../providers/ble_providers.dart';
import 'encounter_helpers.dart';

final _asciiFormatter =
    FilteringTextInputFormatter.allow(RegExp(r'[\x20-\x7E]'));

const _prefectureNames = [
  '北海道', '青森', '岩手', '宮城', '秋田', '山形', '福島',
  '茨城', '栃木', '群馬', '埼玉', '千葉', '東京', '神奈川',
  '新潟', '富山', '石川', '福井', '山梨', '長野',
  '岐阜', '静岡', '愛知', '三重',
  '滋賀', '京都', '大阪', '兵庫', '奈良', '和歌山',
  '鳥取', '島根', '岡山', '広島', '山口',
  '徳島', '香川', '愛媛', '高知',
  '福岡', '佐賀', '長崎', '熊本', '大分', '宮崎', '鹿児島', '沖縄',
];

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
  int _prefecture = -1;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(appProvider).ownProfile;
    _nameCtrl = TextEditingController(text: profile?.name ?? '');
    _colorIndex = profile?.colorIndex ?? 0;
    _template = profile?.template ?? const TemplateMessage();
    _prefecture = profile?.prefecture ?? -1;
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
      showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('名前を入力してください'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final existing = ref.read(appProvider).ownProfile;
    await ref.read(appProvider.notifier).saveOwnProfile(
          OwnProfile(
            name: name,
            colorIndex: _colorIndex,
            prefecture: _prefecture,
            template: _template,
            registeredAt: existing?.registeredAt,
          ),
        );
    if (!widget.isFirstLaunch && context.mounted) {
      showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('保存しました'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showPicker<T>({
    required String title,
    required List<String> options,
    required int currentIndex,
    required ValueChanged<int> onSelected,
    bool hasNone = true,
  }) async {
    int tempIndex = hasNone ? currentIndex + 1 : currentIndex;
    final allOptions = hasNone ? ['未設定', ...options] : options;

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => Container(
        height: 300,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: const Text('キャンセル'),
                  onPressed: () => Navigator.pop(context),
                ),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 16)),
                CupertinoButton(
                  child: const Text('完了'),
                  onPressed: () {
                    onSelected(hasNone ? tempIndex - 1 : tempIndex);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            Expanded(
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(
                    initialItem: tempIndex.clamp(0, allOptions.length - 1)),
                itemExtent: 40,
                onSelectedItemChanged: (i) => tempIndex = i,
                children: allOptions
                    .map((s) => Center(child: Text(s)))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(appProvider).ownProfile;
    final registeredAt = profile?.registeredAt;
    final initial =
        _nameCtrl.text.isNotEmpty ? _nameCtrl.text.characters.first : '?';
    final bright = Theme.of(context).brightness;

    final avatar = GestureDetector(
      onTap: () => _showColorPicker(),
      child: Column(
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: avatarColors[_colorIndex],
            child: Text(
              initial,
              style: const TextStyle(
                  fontSize: 40,
                  color: Colors.white,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 6),
          Text('タップして色を変更',
              style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context))),
        ],
      ),
    );

    final catIdx = _template.hobbyCategory.clamp(
        0, TemplateMessage.hobbyDetails.length - 1);
    final detailItems = TemplateMessage.hobbyDetails[catIdx];
    final safeDetail = _template.hobbyDetail == -1
        ? -1
        : _template.hobbyDetail.clamp(0, detailItems.length - 1);

    final prefLabel = _prefecture < 0 || _prefecture >= _prefectureNames.length
        ? '未設定'
        : _prefectureNames[_prefecture];

    final statusLabel = _template.statusIndex < 0
        ? '未回答'
        : TemplateMessage.statusList[
            _template.statusIndex.clamp(0, TemplateMessage.statusList.length - 1)];

    final hobbyLabel = _template.hobbyCategory < 0
        ? '未回答'
        : TemplateMessage.hobbyCategories[
            _template.hobbyCategory.clamp(0, TemplateMessage.hobbyCategories.length - 1)];

    final detailLabel = _template.hobbyDetail < 0 || _template.hobbyCategory < 0
        ? '未回答'
        : detailItems[safeDetail.clamp(0, detailItems.length - 1)];

    final phraseLabel = _template.phraseIndex < 0
        ? '未回答'
        : TemplateMessage.phraseList[
            _template.phraseIndex.clamp(0, TemplateMessage.phraseList.length - 1)];

    final body = CustomScrollView(
      slivers: [
        if (!widget.isFirstLaunch)
          const SliverAppBar.large(title: Text('プロフィール'))
        else
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Profile Setup'),
            automaticallyImplyLeading: false,
            border: null,
          ),
        SliverToBoxAdapter(
          child: Column(
            children: [
              const SizedBox(height: 24),
              avatar,
              const SizedBox(height: 32),

              // ─── 名前 ────────────────────────────────────────────────
              CupertinoListSection.insetGrouped(
                header: const Text('名前'),
                children: [
                  CupertinoTextFormFieldRow(
                    controller: _nameCtrl,
                    maxLength: 10,
                    keyboardType: TextInputType.emailAddress,
                    inputFormatters: [_asciiFormatter],
                    placeholder: 'English only · max 10 chars',
                    prefix: const Icon(CupertinoIcons.person,
                        color: CupertinoColors.systemBlue, size: 20),
                    onChanged: (_) => _sanitizeName(),
                    style: TextStyle(
                        color: bright == Brightness.dark
                            ? CupertinoColors.white
                            : CupertinoColors.black),
                  ),
                ],
              ),

              // ─── ひとこと ─────────────────────────────────────────────
              CupertinoListSection.insetGrouped(
                header: const Text('ひとこと設定'),
                children: [
                  _PickerRow(
                    label: '状態',
                    value: statusLabel,
                    onTap: () => _showPicker(
                      title: '状態',
                      options: TemplateMessage.statusList,
                      currentIndex: _template.statusIndex,
                      onSelected: (i) =>
                          setState(() => _template = _template.copyWith(statusIndex: i)),
                    ),
                  ),
                  _PickerRow(
                    label: '趣味カテゴリ',
                    value: hobbyLabel,
                    onTap: () => _showPicker(
                      title: '趣味カテゴリ',
                      options: TemplateMessage.hobbyCategories,
                      currentIndex: _template.hobbyCategory,
                      onSelected: (i) => setState(() => _template =
                          _template.copyWith(hobbyCategory: i, hobbyDetail: i == -1 ? -1 : 0)),
                    ),
                  ),
                  if (_template.hobbyCategory != -1)
                    _PickerRow(
                      label: '趣味詳細',
                      value: detailLabel,
                      onTap: () => _showPicker(
                        title: '趣味詳細',
                        options: detailItems,
                        currentIndex: safeDetail,
                        onSelected: (i) =>
                            setState(() => _template = _template.copyWith(hobbyDetail: i)),
                      ),
                    ),
                  _PickerRow(
                    label: '出身地',
                    value: prefLabel,
                    onTap: () => _showPicker(
                      title: '出身地',
                      options: _prefectureNames.toList(),
                      currentIndex: _prefecture,
                      onSelected: (i) => setState(() => _prefecture = i),
                    ),
                  ),
                  _PickerRow(
                    label: '締めの一言',
                    value: phraseLabel,
                    onTap: () => _showPicker(
                      title: '締めの一言',
                      options: TemplateMessage.phraseList,
                      currentIndex: _template.phraseIndex,
                      onSelected: (i) =>
                          setState(() => _template = _template.copyWith(phraseIndex: i)),
                    ),
                  ),
                ],
              ),

              // ─── プレビュー ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: CupertinoColors.secondarySystemGroupedBackground
                        .resolveFrom(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('プレビュー',
                          style: TextStyle(
                              fontSize: 11,
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context))),
                      const SizedBox(height: 6),
                      Text(
                        '${_template.statusText}  ·  ${_template.hobbyCategoryText}(${_template.hobbyDetailText})  ·  ${_template.phraseText}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

              if (registeredAt != null) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.calendar,
                          size: 15,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context)),
                      const SizedBox(width: 6),
                      Text('登録日',
                          style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context))),
                      const Spacer(),
                      Text(fmtDate(registeredAt),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: CupertinoButton.filled(
                  onPressed: _save,
                  child: Text(widget.isFirstLaunch ? 'はじめる' : '保存'),
                ),
              ),
              if (widget.isFirstLaunch) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Your name and template message are shared with nearby people.\nEnglish name only. Anonymous OK.',
                    style: TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.secondaryLabel
                            .resolveFrom(context)),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 48),
            ],
          ),
        ),
      ],
    );

    return widget.isFirstLaunch ? Scaffold(body: body) : body;
  }

  void _showColorPicker() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Avatar Color',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(avatarColors.length, (i) {
                final selected = i == _colorIndex;
                return GestureDetector(
                  onTap: () {
                    setState(() => _colorIndex = i);
                    Navigator.pop(context);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: avatarColors[i],
                      border: selected
                          ? Border.all(
                              color: CupertinoColors.label.resolveFrom(context),
                              width: 3)
                          : null,
                    ),
                    child: selected
                        ? const Icon(CupertinoIcons.checkmark,
                            color: Colors.white, size: 22)
                        : null,
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _PickerRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: Text(label),
      additionalInfo: Text(
        value,
        style: TextStyle(
            color: CupertinoColors.secondaryLabel.resolveFrom(context)),
      ),
      trailing: const CupertinoListTileChevron(),
      onTap: onTap,
    );
  }
}
