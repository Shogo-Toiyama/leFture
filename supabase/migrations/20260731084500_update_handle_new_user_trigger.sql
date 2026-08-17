-- ユーザー登録時に user_profiles を自動作成するトリガー関数の改訂
-- ソーシャルログイン側の full_name / name は使用せず、アプリで指定された username / display_name のみを初期使用する

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
declare
  inserted_username text;
  inserted_avatar_url text;
begin
  -- ① Username の決定ロジック
  -- メタデータからアプリで指定された 'username' または 'display_name' のみを探す
  -- (ソーシャルアカウントの本名である 'full_name' や 'name' は一切使用しない)
  inserted_username := coalesce(
    new.raw_user_meta_data->>'username',
    new.raw_user_meta_data->>'display_name'
  );

  -- ② アバターURL の決定ロジック
  inserted_avatar_url := coalesce(
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'avatar_url_https',
    new.raw_user_meta_data->>'picture'
  );

  -- ③ user_profiles テーブルへのデータ挿入 (CONFLICT 時は既存値を保持)
  insert into public.user_profiles (
    id, 
    username, 
    avatar_url
  )
  values (
    new.id,
    inserted_username,
    inserted_avatar_url
  )
  on conflict (id) do update set
    username = coalesce(user_profiles.username, excluded.username),
    avatar_url = coalesce(user_profiles.avatar_url, excluded.avatar_url);

  return new;
end;
$$ language plpgsql security definer;
