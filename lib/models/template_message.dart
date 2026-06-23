class TemplateMessage {
  static const kNotSet = -1; // 未回答

  static const statusList = [
    'すれ違い中！',
    '学校・職場にいます',
    'ガチで暇してます',
    '忙しくて修羅場です',
    '外出中です',
    'お家でまったり中',
    '移動中です',
    'イベント参加中！',
  ];

  static const hobbyCategories = [
    'ゲーム',
    'アニメ・漫画',
    '音楽・ライブ',
    'スポーツ',
    'グルメ・カフェ',
    '旅行・アウトドア',
    '映画・ドラマ',
    '読書・勉強',
  ];

  static const List<List<String>> hobbyDetails = [
    ['ガチ勢', 'エンジョイ勢', 'レトロゲー好き', 'スマホゲーメイン'],
    ['アニメ派', '漫画派', '声優オタク', 'BL・TL好き'],
    ['邦楽派', '洋楽派', 'ライブ命', 'DTM・制作もやる'],
    ['観戦派', 'プレイヤー', '筋トレ中', 'マラソン好き'],
    ['ラーメン道', 'スイーツ探求', 'カフェ巡り', '料理好き'],
    ['国内旅行派', '海外旅行派', 'キャンプ好き', '散歩・街歩き'],
    ['映画館派', 'サブスク派', 'ホラー好き', 'アクション好き'],
    ['受験・勉強中', '読書好き', '資格取得中', 'ビジネス書派'],
  ];

  static const phraseList = [
    'お気軽にどうぞ！',
    '気が合ったらまた会おう',
    'よろしく！',
    '話しかけてね！',
    '仲良くしましょう',
    'よい一日を！',
    'また会いましょう',
    '一期一会ですね',
  ];

  final int statusIndex;
  final int hobbyCategory;
  final int hobbyDetail;
  final int phraseIndex;

  const TemplateMessage({
    this.statusIndex = 0,
    this.hobbyCategory = 0,
    this.hobbyDetail = 0,
    this.phraseIndex = 0,
  });

  String get statusText => statusIndex == kNotSet
      ? '未回答'
      : statusList[statusIndex.clamp(0, statusList.length - 1)];

  String get hobbyCategoryText => hobbyCategory == kNotSet
      ? '未回答'
      : hobbyCategories[hobbyCategory.clamp(0, hobbyCategories.length - 1)];

  String get hobbyDetailText {
    if (hobbyDetail == kNotSet || hobbyCategory == kNotSet) return '未回答';
    final cat = hobbyCategory.clamp(0, hobbyDetails.length - 1);
    final details = hobbyDetails[cat];
    return details[hobbyDetail.clamp(0, details.length - 1)];
  }

  String get phraseText => phraseIndex == kNotSet
      ? '未回答'
      : phraseList[phraseIndex.clamp(0, phraseList.length - 1)];

  TemplateMessage copyWith({
    int? statusIndex,
    int? hobbyCategory,
    int? hobbyDetail,
    int? phraseIndex,
  }) =>
      TemplateMessage(
        statusIndex: statusIndex ?? this.statusIndex,
        hobbyCategory: hobbyCategory ?? this.hobbyCategory,
        hobbyDetail: hobbyDetail ?? this.hobbyDetail,
        phraseIndex: phraseIndex ?? this.phraseIndex,
      );
}
