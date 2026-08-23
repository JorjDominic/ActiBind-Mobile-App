begin;

-- Database invariants for the window-detail child table. This script is intended
-- for `supabase test db` and rolls back all fixtures.
create extension if not exists pgtap with schema extensions;
select plan(8);

select has_table('public', 'device_app_window_activity', 'window activity table exists');
select has_index(
  'public',
  'device_app_window_activity',
  'device_app_window_activity_identity_key',
  'activity/window identity is unique'
);
select col_not_null(
  'public',
  'device_app_window_activity',
  'window_title',
  'window title is required'
);
select has_fk(
  'public',
  'device_app_window_activity',
  'window detail has a parent foreign key'
);
select fk_ok(
  'public',
  'device_app_window_activity',
  'activity_id',
  'public',
  'device_app_activity',
  'id',
  'activity ID references app activity'
);
select has_trigger(
  'public',
  'device_app_window_activity',
  'device_app_window_activity_set_updated_at',
  'updated_at trigger exists'
);
select table_privs_are(
  'public',
  'device_app_window_activity',
  'anon',
  array[]::text[],
  'anonymous clients have no direct table privileges'
);
select function_privs_are(
  'public',
  'edge_upload_device_app_window_activity',
  array['text', 'uuid', 'text', 'jsonb'],
  'service_role',
  array['EXECUTE'],
  'service role can invoke the secure upload RPC'
);

select * from finish();
rollback;
