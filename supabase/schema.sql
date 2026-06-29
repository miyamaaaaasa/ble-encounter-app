-- ================================================================
-- はじめましてこんにちは — Supabase スキーマ
-- supabase.com の SQL Editor に貼り付けて実行してください
-- ================================================================

-- ① ユーザープロフィール（Supabase Authのanonymous userと1:1）
CREATE TABLE IF NOT EXISTS public.users (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  display_name    TEXT,
  color_index     INT DEFAULT 0,
  piece_data      JSONB,          -- 16x16 ピクセルインデックス配列 (256整数)
  piece_palette   JSONB           -- 将来拡張用（現在は固定パレット使用）
);

-- ② 使い捨てトークン（BLEで流すID、24時間で自動回転）
CREATE TABLE IF NOT EXISTS public.tokens (
  token           TEXT PRIMARY KEY,           -- 16バイトランダム（hex 32文字）
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  issued_at       TIMESTAMPTZ DEFAULT NOW(),
  expires_at      TIMESTAMPTZ NOT NULL
);

-- ③ 収集ピース（誰が誰のピースを持っているか）
CREATE TABLE IF NOT EXISTS public.collected_pieces (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  collector_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  owner_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  first_met_at    TIMESTAMPTZ DEFAULT NOW(),
  last_met_at     TIMESTAMPTZ DEFAULT NOW(),
  meet_count      INT DEFAULT 1,
  piece_snapshot  JSONB,          -- 出会い時のピースのスナップショット
  UNIQUE(collector_id, owner_id)
);

-- インデックス
CREATE INDEX IF NOT EXISTS tokens_user_id_idx ON public.tokens(user_id);
CREATE INDEX IF NOT EXISTS tokens_expires_idx ON public.tokens(expires_at);
CREATE INDEX IF NOT EXISTS pieces_collector_idx ON public.collected_pieces(collector_id);

-- ================================================================
-- Row Level Security (RLS)
-- ================================================================
ALTER TABLE public.users           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tokens          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.collected_pieces ENABLE ROW LEVEL SECURITY;

-- users: 自分のデータのみ読み書き
CREATE POLICY "users_own" ON public.users
  FOR ALL USING (auth.uid() = id);

-- tokens: 誰でも読める（解析のため）、書き込みは本人のみ
CREATE POLICY "tokens_read_all" ON public.tokens
  FOR SELECT USING (true);
CREATE POLICY "tokens_write_own" ON public.tokens
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "tokens_delete_own" ON public.tokens
  FOR DELETE USING (auth.uid() = user_id);

-- collected_pieces: 自分が収集者のもののみ
CREATE POLICY "pieces_own" ON public.collected_pieces
  FOR ALL USING (auth.uid() = collector_id);

-- ================================================================
-- RPC Functions
-- ================================================================

-- 新トークン発行（クライアントから呼ぶ）
CREATE OR REPLACE FUNCTION public.issue_token()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_token TEXT;
BEGIN
  -- 暗号学的に安全な16バイトトークン生成
  new_token := encode(gen_random_bytes(16), 'hex');

  -- このユーザーの期限切れトークンを削除
  DELETE FROM public.tokens
    WHERE user_id = auth.uid() AND expires_at < NOW();

  -- 新トークンを挿入（24時間有効）
  INSERT INTO public.tokens (token, user_id, expires_at)
    VALUES (new_token, auth.uid(), NOW() + INTERVAL '24 hours')
    ON CONFLICT (token) DO NOTHING;

  RETURN new_token;
END;
$$;

-- トークンリストを解析してユーザー情報を返す（ゲート時に使用）
CREATE OR REPLACE FUNCTION public.resolve_tokens(token_list TEXT[])
RETURNS TABLE(
  token         TEXT,
  user_id       UUID,
  display_name  TEXT,
  color_index   INT,
  piece_data    JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    SELECT
      t.token,
      t.user_id,
      u.display_name,
      u.color_index,
      u.piece_data
    FROM public.tokens t
    JOIN public.users u ON u.id = t.user_id
    WHERE t.token = ANY(token_list)
      -- 48時間以内のトークンを解析対象（すべてのゲートタイミングをカバー）
      AND t.issued_at > NOW() - INTERVAL '48 hours';
END;
$$;

-- 初回登録: auth.users作成時にusersテーブルに行を作る
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id)
  VALUES (NEW.id)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- ユーザー作成トリガー
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
