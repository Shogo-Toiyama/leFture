import 'package:lefture/domain/entities/course_attribute.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'course_attribute_repository_supabase.g.dart';

@Riverpod(keepAlive: true)
CourseAttributeRepositorySupabase courseAttributeRepository(Ref ref) {
  return CourseAttributeRepositorySupabase();
}

class CourseAttributeRepositorySupabase {
  static const _table = 'course_attributes';

  String _requireUid() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not authenticated');
    return uid;
  }

  /// 指定タイプ（"year", "term", "subject", "school"）の一覧を取得
  Future<List<CourseAttribute>> listByType(String attributeType) async {
    final uid = _requireUid();

    final rows = await supabase
        .from(_table)
        .select()
        .eq('user_id', uid)
        .eq('attribute_type', attributeType)
        .isFilter('deleted_at', null)
        .order('attribute_name', ascending: true);

    return rows.map((e) => CourseAttribute.fromMap(e)).toList();
  }

  /// 全アトリビュートを取得（仮想フォルダツリー構築用）
  Future<List<CourseAttribute>> listAll() async {
    final uid = _requireUid();

    final rows = await supabase
        .from(_table)
        .select()
        .eq('user_id', uid)
        .isFilter('deleted_at', null)
        .order('attribute_type', ascending: true)
        .order('attribute_name', ascending: true);

    return rows.map((e) => CourseAttribute.fromMap(e)).toList();
  }

  /// 存在すれば返す、なければ作って返す
  Future<CourseAttribute> getOrCreate({
    required String attributeType,
    required String attributeName,
  }) async {
    final uid = _requireUid();

    final existing = await supabase
        .from(_table)
        .select()
        .eq('user_id', uid)
        .eq('attribute_type', attributeType)
        .eq('attribute_name', attributeName)
        .maybeSingle();

    if (existing != null) {
      return CourseAttribute.fromMap(existing);
    }

    final inserted = await supabase
        .from(_table)
        .insert({
          'user_id': uid,
          'attribute_type': attributeType,
          'attribute_name': attributeName,
        })
        .select()
        .single();

    return CourseAttribute.fromMap(inserted);
  }

  Future<void> deleteAttribute(String attributeId) async {
    final uid = _requireUid();
    await supabase
        .from(_table)
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', attributeId)
        .eq('user_id', uid);
  }
}
