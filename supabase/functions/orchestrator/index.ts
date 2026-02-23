// supabase/functions/orchestrator/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'

serve(async (req) => {
  try {
    const payload = await req.json()
    // SupabaseのDatabase Webhookから送られてくるデータ
    const { type, record, old_record } = payload

    // 1. 反応すべきイベントかチェック
    // - INSERT: start_analysisでタスクがドバッと作られた時（最初のタスクを発火させるため）
    // - UPDATE: どこかのAIワーカーが処理を終えて 'COMPLETED' になった時
    const isNew = type === 'INSERT' && record.status === 'PENDING'
    const isNewlyCompleted = type === 'UPDATE' && record.status === 'COMPLETED' && old_record?.status !== 'COMPLETED'

    if (!isNew && !isNewlyCompleted) {
      return new Response("Not a triggerable state. Ignoring.", { status: 200 })
    }

    console.log(`🎼 Orchestrator waking up! Triggered by Task: ${record.task_type} (${type})`)

    // 2. Service Role Key を使って管理者権限でDBにアクセスする
    // ※ Webhookはユーザーではなく「システム」として動くので、RLSをバイパスする権限が必要です
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const jobId = record.job_id

    // 3. このジョブに紐づく「すべてのタスク」の最新状態を取得
    const { data: allTasks, error: fetchError } = await supabaseAdmin
      .from('processing_tasks')
      .select('*')
      .eq('job_id', jobId)

    if (fetchError || !allTasks) throw fetchError

    // すでに完了しているタスクのリスト（例: ['MERGE_TRANSCRIPTS', 'SENTENCE_REVIEW']）
    const completedTypes = allTasks
      .filter(t => t.status === 'COMPLETED')
      .map(t => t.task_type)

    // 4. DAG（依存関係）の評価：次に実行できるタスクを探す！
    const readyTasks = allTasks.filter(t => {
      // PENDING（待機中）のものだけを対象にする
      if (t.status !== 'PENDING') return false
      
      // JSONBで保存されている依存関係の配列をパース
      const deps = typeof t.dependencies === 'string' ? JSON.parse(t.dependencies) : (t.dependencies || [])
      
      // 依存しているタスクが「すべて」completedTypesに含まれていれば実行可能！
      return deps.every((dep: string) => completedTypes.includes(dep))
    })

    if (readyTasks.length === 0) {
      console.log("⏸️ No ready tasks found at this moment.")
      return new Response("No ready tasks", { status: 200 })
    }

    console.log(`🚀 Found ${readyTasks.length} ready task(s):`, readyTasks.map(t => t.task_type))

    // 5. 実行可能なタスクを処理
    for (const task of readyTasks) {
      // 5-1. 二重起動を防ぐため、まずDBのステータスを 'QUEUED' に更新する
      const { error: updateError } = await supabaseAdmin
        .from('processing_tasks')
        .update({ status: 'QUEUED' })
        .eq('id', task.id)
        // ※ここでeq('status', 'PENDING')を入れると、レースコンディションをさらに強固に防げます
        .eq('status', 'PENDING') 

      if (updateError) {
        console.error(`Failed to update task ${task.task_type} to QUEUED:`, updateError)
        continue;
      }

      // 5-2. Cloud Run (FastAPI) の受付窓口に「このタスクをキューに入れて！」と依頼する
      const cloudRunUrl = Deno.env.get('CLOUD_RUN_URL')
      if (cloudRunUrl) {
        // ※このエンドポイントは次のステップでFastAPI側に作ります
        await fetch(`${cloudRunUrl}/enqueue-task`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            job_id: jobId,
            task_id: task.id,
            task_type: task.task_type
          })
        }).catch(err => console.error(`Error pinging Cloud Run for ${task.task_type}:`, err))
      } else {
        console.log(`⚠️ CLOUD_RUN_URL is not set. Skipped pinging Cloud Run for ${task.task_type}.`)
      }
    }

    return new Response("Orchestration successful", { status: 200 })

  } catch (error: any) {
    console.error("Orchestrator Error:", error)
    return new Response(`Error: ${error.message}`, { status: 500 })
  }
})