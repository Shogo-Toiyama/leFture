// supabase/functions/start_analysis/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'

// アプリから呼び出すためのCORS設定
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // 1. CORSのプリフライトリクエスト対応
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 2. Flutterから送られてきたデータを受け取る
    const { lecture_id, expected_chunks } = await req.json()
    
    const authHeader = req.headers.get('Authorization')
    console.log(`🔑 Auth Header exists: ${!!authHeader}`)

    if (!lecture_id || expected_chunks === undefined) {
      throw new Error("Missing required parameters: lecture_id or expected_chunks")
    }

    console.log(`🚀 Start Analysis called for Lecture: ${lecture_id}, Chunks: ${expected_chunks}`)

    // 3. ユーザーの認証情報を引き継いでSupabaseクライアントを作成（これでRLSも突破できる）
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    )

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(token)

    if (authError || !user) {
      console.error("🚨 Auth Error details:", authError)
      throw new Error(`Unauthorized user: ${authError?.message || 'No user found'}`)
    }

    const ownerId = user.id

    // 4. 親ジョブを作成 (processing_jobs)
    const { data: job, error: jobError } = await supabaseClient
      .from('processing_jobs')
      .insert({
        lecture_id: lecture_id,
        owner_id: ownerId,
        expected_chunks: expected_chunks,
        status: 'PENDING'
      })
      .select()
      .single()

    if (jobError) {
      console.error("Job creation error:", jobError)
      throw new Error("Failed to create processing_job")
    }
    
    const jobId = job.id

    // 5. タスクの設計図（DAG）を定義
    const tasks: Array<{ task_type: string, dependencies: string[] }> = []
    tasks.push(
      { task_type: 'CHECK_AND_ASSEMBLE', dependencies: [] },
      { task_type: 'ROLE_CLASSIFICATION', dependencies: ['CHECK_AND_ASSEMBLE'] },
      { task_type: 'CORE_EXTRACTION', dependencies: ['ROLE_CLASSIFICATION'] },
      { task_type: 'ANNOUNCEMENT_GENERATION', dependencies: ['ROLE_CLASSIFICATION'] },
      
      { task_type: 'TOPIC_MAPPING', dependencies: ['CORE_EXTRACTION'] },
      { task_type: 'REVIEW_CARD', dependencies: ['CORE_EXTRACTION'] },
      { task_type: 'FUN_FACTS', dependencies: ['CORE_EXTRACTION'] },
      { task_type: 'DETAIL_CONTENTS', dependencies: ['CORE_EXTRACTION'] },
      
      { task_type: 'IMAGE_GENERATION', dependencies: ['REVIEW_CARD'] }
    )

    // 6. DBに挿入しやすい形に整形
    const insertData = tasks.map(t => ({
      job_id: jobId,
      task_type: t.task_type,
      dependencies: JSON.stringify(t.dependencies), // JSONBカラムに入れるために文字列化
      status: 'PENDING'
    }))

    // 7. 子タスクを一気に登録 (processing_tasks)
    const { error: tasksError } = await supabaseClient
      .from('processing_tasks')
      .insert(insertData)

    if (tasksError) {
      console.error("Tasks creation error:", tasksError)
      throw new Error("Failed to create processing_tasks")
    }

    // 大成功！
    return new Response(
      JSON.stringify({ message: "Analysis started successfully", job_id: jobId }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error: any) {
    console.error("Function Error:", error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    )
  }
})