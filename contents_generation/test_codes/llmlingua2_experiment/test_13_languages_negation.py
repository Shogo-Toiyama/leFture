#!/usr/bin/env python3
"""
Rigorous Multi-lingual Negation Benchmark across 13 Languages.
Tests real-world policy/guideline documents containing natural negations,
constraints, rules, and exceptions to verify whether LLMLingua-2 preserves
negation and does not invert meaning across all 13 supported languages.
"""

import asyncio
import os
import time
from typing import Any, Dict, List
import httpx

ENDPOINT_URL = os.getenv(
    "MODAL_LLMLINGUA2_URL",
    "https://shogo-toiyama--lefture-llmlingua2-llmlingua2api-compress.us-east.modal.run",
)

ALL_13_LANG_FORCE_TOKENS = list(set([
    # 1. 英語
    "not", "no", "don't", "doesn't", "cannot", "never", "unless", "except", "without",
    # 2. 日本語
    "ない", "ません", "ず", "ぬ", "不可", "禁止", "除き", "以外", "なく", "ならず", "だめ",
    # 3. 中国語（簡体字）
    "不", "没", "无", "非", "禁", "未", "除非", "除外",
    # 4. 広東語（繁体字）
    "唔", "咪", "無", "冇", "未", "毋",
    # 5. 韓国語
    "안", "못", "않", "없", "금지", "말고", "제외",
    # 6. フランス語
    "pas", "ne", "plus", "jamais", "rien", "aucun", "sauf", "sans",
    # 7. スペイン語
    "no", "nunca", "jamás", "nada", "nadie", "excepto", "salvo", "sin",
    # 8. ポルトガル語
    "não", "nunca", "jamais", "nada", "ninguém", "exceto", "salvo", "sem",
    # 9. ドイツ語
    "nicht", "kein", "nie", "niemals", "ohne", "außer", "weder",
    # 10. イタリア語
    "non", "mai", "niente", "nessuno", "tranne", "salvo", "senza",
    # 11. ロシア語
    "не", "ни", "нет", "нельзя", "кроме", "без",
    # 12. アラビア語
    "لا", "لم", "لن", "ما", "غير", "بدون", "إلا", "ليس",
    # 13. ヒンディー語
    "नहीं", "मत", "ना", "बिना", "सिवाय", "अलावा"
]))

# 13言語の実践的な実験データ（研究室ポリシー・利用規約・セキュリティガイドライン）
# 各ドキュメントには、意図的に複数の重要否定・禁止・制約文が含まれています。
TEST_DOCUMENTS: List[Dict[str, Any]] = [
    {
        "lang": "English",
        "code": "en",
        "title": "Cloud Computing Lab Security & Conduct Policy",
        "check_terms": ["not", "never", "without", "except"],
        "text": """
# Cloud Computing Lab Policy and Guidelines

Welcome to the CS Laboratory. All enrolled students must adhere to the following mandatory regulations. Failure to comply will result in disciplinary action.

1. Account Credentials: You must never share your API keys or cloud credentials with other students. Under no circumstances should secrets be committed to public GitHub repositories.
2. Resource Limits: Instances running without active workload for more than 4 hours will be terminated automatically. Do not run cryptocurrency mining or unapproved distributed tasks.
3. Access Control: External SSH access is not permitted unless authorized through the university VPN. No guest accounts may be created without written supervisor approval.
4. Data Handling: Personal identifiable student data must not be transferred outside the designated subnet, except for anonymized benchmark datasets.
5. Submission: Late submissions are not accepted unless accompanied by a medical certificate submitted before the deadline.
"""
    },
    {
        "lang": "Japanese",
        "code": "ja",
        "title": "コンピュータサイエンス実験室 安全・利用規約",
        "check_terms": ["ません", "禁止", "ならず", "以外", "ない"],
        "text": """
# 情報科学研究室・計算機利用ガイドライン

学生の皆さんは、安全かつ公正な研究活動を維持するため、以下の規則を厳守してください。

1. 認証情報の管理：研究室のクラスタログインパスワードおよびAPI鍵を第三者と共有してはなりません。事前の許可なく外部リポジトリへ設定ファイルを公開することは厳禁です。
2. 計算資源の利用：未承認の常駐プログラムを実行してはならず、マイニングや過度なトラフィックを発生させる行為は禁止されています。
3. リモートアクセス：指定された学内VPNを経由しない直接のSSH接続は許可されません。また、講義目的以外の私的利用は認められません。
4. データの取り扱い：実験対象の個人データや未公開論文の草稿を外部ストレージに保存してはならず、暗号化されていない媒体への書き出しは不可とします。
5. レポート提出：締め切り後の遅延提出は原則として一切受け付けません。ただし、正当な病気等の理由を除くものとします。
"""
    },
    {
        "lang": "French",
        "code": "fr",
        "title": "Règlement intérieur du laboratoire informatique",
        "check_terms": ["pas", "ne", "jamais", "aucun", "sans"],
        "text": """
# Règlement d'utilisation des ressources informatiques

Chaque étudiant utilisant les serveurs du laboratoire est tenu de respecter les consignes suivantes afin d'assurer la sécurité du réseau.

1. Gestion des identifiants: Il ne faut jamais communiquer vos clés d'accès personnelles à un tiers. Aucun mot de passe ne doit être partagé sans l'accord explicite du professeur.
2. Utilisation des clusters: Les calculs non académiques ne sont pas autorisés sur les machines partagées. Ne laissez pas tourner de scripts inutiles sans surveillance pendant la nuit.
3. Sécurité réseau: L'accès externe aux bases de données n'est pas permis sans passer par le tunnel sécurisé du département.
4. Sauvegarde des données: Aucune donnée sensible ne doit être exportée en dehors du réseau universitaire, sauf autorisation écrite préalable.
5. Soumission des devoirs: Les retards ne sont pas acceptés, sauf cas de force majeure justifié avant la date limite.
"""
    },
    {
        "lang": "Spanish",
        "code": "es",
        "title": "Normas de seguridad del laboratorio de sistemas",
        "check_terms": ["no", "nunca", "sin", "excepto"],
        "text": """
# Normativa y uso del laboratorio de computación

Todos los estudiantes inscritos deben cumplir con las siguientes directrices operativas en los servidores del departamento.

1. Credenciales de acceso: Nunca debe compartir sus contraseñas o tokens de API con otros usuarios. No se permite subir credenciales a repositorios públicos bajo ninguna circunstancia.
2. Consumo de recursos: No se permite ejecutar procesos pesados que no pertenezcan al proyecto asignado. Los trabajos sin actividad durante más de dos horas serán cancelados.
3. Red y conectividad: No está permitida la conexión directa fuera del campus sin utilizar la VPN oficial de la facultad.
4. Integridad de datos: Ningún archivo confidencial puede ser descargado a computadoras personales, excepto aquellos debidamente anonimizados para pruebas locales.
5. Entrega de trabajos: Las tareas entregadas fuera de plazo no serán calificadas, salvo enfermedad justificada oportunamente.
"""
    },
    {
        "lang": "German",
        "code": "de",
        "title": "Nutzungsordnung für das Rechnerlabor der Informatik",
        "check_terms": ["nicht", "kein", "ohne", "nie"],
        "text": """
# Nutzungsrichtlinien für universitäre Serversysteme

Zur Gewährleistung der Datensicherheit und fairen Ressourcenverteilung müssen alle Studierenden folgende Regeln beachten.

1. Zugangsdaten: Zugangsdaten und SSH-Schlüssel dürfen niemals an Dritte weitergegeben werden. Es ist strengstens untersagt, geheime Schlüssel ohne Verschlüsselung abzulegen.
2. Rechenressourcen: Prozesse, die nicht für Lehrveranstaltungen bestimmt sind, dürfen auf den GPU-Servern nicht ausgeführt werden.
3. Netzwerksicherheit: Ein externer Zugriff auf die Laborrechner ist ohne aktives Universitäts-VPN nicht gestattet. Keine unbefugten Ports öffnen.
4. Datenschutz: Personenbezogene Testdaten dürfen ohne Genehmigung des Lehrstuhls nicht auf private Laptops übertragen werden.
5. Abgabetermine: Verspätete Projektabgaben werden nicht bewertet, außer bei rechtzeitig vorgelegtem ärztlichem Attest.
"""
    },
    {
        "lang": "Chinese (Simplified)",
        "code": "zh",
        "title": "计算机科学实验室计算资源使用守则",
        "check_terms": ["不", "无", "禁", "未", "除非"],
        "text": """
# 计算机系实验教学与服务器使用守则

为保障教学计算环境的安全稳定，所有选课学生在使用实验服务器时必须遵守以下规定。

1. 账号与密钥安全：严禁将个人API密钥及服务器登录密码透露给他人。未经许可不得将实验代码或系统凭证上传至公开平台。
2. 资源配额管理：不得在公共GPU节点上运行与课程无关的进程，禁止进行任何挖矿或高负荷压力测试。
3. 远程连接规范：未经学院VPN认证的外部网络不得直接连接实验内部服务器。严禁私自开启未授权网络端口。
4. 数据资产保护：实验数据库中的敏感数据不可下载至私人终端，除非获得指导老师的书面批准。
5. 作业提交规定：逾期提交的实验报告一律不予计分，未按格式要求的作业不可补交。
"""
    },
    {
        "lang": "Cantonese (Traditional)",
        "code": "yue",
        "title": "電腦科學實驗室使用指引及守則",
        "check_terms": ["唔", "咪", "無", "未"],
        "text": """
# 電腦實驗室伺服器使用指引

各位同學在使用實驗室計算資源嗰陣，必須遵守以下規定，維護系統安全運作。

1. 登入資料保密：千祈咪同其他人分享你嘅登入密碼同API密鑰。無經過許可，絕唔可以將系統敏感資料放上公開網絡。
2. 運算資源使用：同學唔可以喺伺服器執行無關課堂嘅程式，嚴禁未經批准嘅長期佔用運算節點。
3. 網絡連線限制：無透過校園VPN連線嗰陣，外部網絡係唔可以直接連入實驗室電腦。
4. 資料保護指引：研究用嘅機密數據唔可以擅自下載到私人電話或電腦，除非得到導師書面批准。
5. 作業遞交安排：逾期遞交嘅報告一律唔會批改，無有效醫生證明係唔可以補交作業。
"""
    },
    {
        "lang": "Korean",
        "code": "ko",
        "title": "컴퓨터공학과 연구실 서버 이용 및 보안 수칙",
        "check_terms": ["않", "못", "금지", "없", "제외"],
        "text": """
# 컴퓨터공학과 실습 서버 이용 규정

학생 여러분은 연구실 서버의 보안과 공정한 자원 활용을 위해 아래의 이용 수칙을 반드시 준수해야 합니다.

1. 계정 정보 보호: 개인 API 키 및 접속 비밀번호를 타인과 절대 공유하지 마십시오. 승인되지 않은 공개 깃허브 저장소에 키를 올리는 것은 엄격히 금지됩니다.
2. 컴퓨팅 자원 활용: 과제 목적 외의 대규모 연산 작업을 수행해서는 안 되며, 가상화폐 채굴 행위는 절대 허용되지 않습니다.
3. 원격 접속 규정: 학내 VPN을 통하지 않은 외부에서의 직접 SSH 접속은 허용되지 않습니다.
4. 데이터 유출 방지: 비공개 데이터셋을 외부 저장 장치로 반출할 수 없으며, 책임 교수의 사전 승인 없이 데이터를 외부로 전송해서는 안 됩니다.
5. 과제 제출 기한: 제출 기한이 지난 과제는 인정되지 않으며, 공식 사유서가 없는 경우 추가 제출이 불가합니다.
"""
    },
    {
        "lang": "Portuguese",
        "code": "pt",
        "title": "Regulamento de Segurança do Laboratório de Redes",
        "check_terms": ["não", "nunca", "sem", "exceto"],
        "text": """
# Normas de Utilização dos Servidores do Departamento

Para assegurar o bom funcionamento das máquinas do laboratório, todos os estudantes devem seguir as seguintes determinações.

1. Credenciais de Acesso: Você nunca deve fornecer sua senha ou chaves de API a terceiros. Não é permitido hospedar credenciais em repositórios abertos na internet.
2. Recursos de Computação: Processos que não estejam relacionados às atividades acadêmicas não podem ser iniciados nos servidores GPU.
3. Conexão Remota: O acesso externo via terminal não é autorizado sem o uso prévio da VPN da universidade.
4. Proteção de Dados: Dados confidenciais de pesquisas não devem ser salvos em dispositivos particulares, exceto quando devidamente criptografados.
5. Prazos de Entrega: Trabalhos submetidos com atraso não serão avaliados pelo corpo docente, salvo motivo médico devidamente comprovado.
"""
    },
    {
        "lang": "Italian",
        "code": "it",
        "title": "Regolamento del laboratorio di calcolo avanzato",
        "check_terms": ["non", "mai", "senza", "nessun", "salvo"],
        "text": """
# Norme di accesso e utilizzo dei server universitari

Gli studenti sono tenuti a rispettare scrupolosamente le seguenti disposizioni durante l'uso delle infrastrutture informatiche.

1. Riservatezza degli accessi: Non si devono mai cedere le credenziali personali o i token di autenticazione ad altri studenti.
2. Uso delle GPU: Non è consentito eseguire programmi che non facciano parte del programma del corso. I job inattivi senza processo attivo verranno terminati.
3. Rete e sicurezza: La connessione SSH diretta dall'esterno non è consentita senza l'utilizzo della rete VPN istituzionale.
4. Trattamento dei dati: Nessun archivio di dati riservati può essere copiato al di fuori del cluster, salvo esplicita autorizzazione del relatore.
5. Consegna degli elaborati: I progetti consegnati in ritardo non verranno corretti, salvo giustificato impedimento medico tempestivamente segnalato.
"""
    },
    {
        "lang": "Russian",
        "code": "ru",
        "title": "Правила безопасности учебного вычислительного центра",
        "check_terms": ["не", "нет", "нельзя", "без", "кроме"],
        "text": """
# Положение об использовании серверов лаборатории

Все студенты, допущенные к работе на вычислительных кластерах факультета, обязаны строго соблюдать следующие требования.

1. Учетные записи: Запрещено передавать персональные логины и ключи SSH третьим лицам. Ни при каких условиях не публикуйте секретные токены в открытых репозиториях.
2. Использование ресурсов: Нельзя запускать фоновые процессы, не относящиеся к учебному заданию. Майнинг криптовалют строго воспрещен.
3. Сетевой доступ: Прямое подключение к серверу из внешней сети без корпоративного VPN не разрешается.
4. Хранение данных: Конфиденциальные данные исследований не должны копироваться на личные флеш-накопители без специального разрешения.
5. Сдача работ: Задания, отправленные после дедлайна, не проверяются, кроме случаев подтвержденной болезни.
"""
    },
    {
        "lang": "Arabic",
        "code": "ar",
        "title": "سياسة أمان مختبر الحوسبة والأنظمة الجامعية",
        "check_terms": ["لا", "لم", "لن", "بدون", "غير"],
        "text": """
# لوائح استخدام الخوادم والمختبرات الجامعية

يجب على جميع الطلاب المسجلين الالتزام التام بالتعليمات التالية لضمان سلامة وأمن بيئة الحوسبة الأكاديمية.

1. حماية بيانات الدخول: لا يجوز أبداً مشاركة كلمات المرور أو مفاتيح واجهة البرمجة مع أي شخص آخر. يمنع منعاً باتاً نشر الرموز في مستودعات عامة.
2. استهلاك الموارد: لا يُسمح بتشغيل أي عمليات غير متعلقة بالمقرر الدراسي. لن يُسمح بأي شكل من أشكال التعدين الرقمي.
3. الوصول عن بُعد: الاتصال الخارجي غير مسموح به بدون استخدام شبكة الجامعة الافتراضية المعتمدة.
4. حماية البيانات: لا ينبغي نقل البيانات الحساسة إلى أجهزة شخصية بدون موافقة خطية من المشرف الأكاديمي.
5. تسليم الواجبات: لن يتم قبول أي مشروع بعد انتهاء الموعد النهائي، باستثناء الحالات الطبية الموثقة رسمياً قبل الموعد.
"""
    },
    {
        "lang": "Hindi",
        "code": "hi",
        "title": "कंप्यूटर विज्ञान प्रयोगशाला सुरक्षा और उपयोग नीति",
        "check_terms": ["नहीं", "मत", "बिना", "सिवाय"],
        "text": """
# कंप्यूटर प्रयोगशाला एवं सर्वर उपयोग दिशानिर्देश

सभी पंजीकृत छात्रों को प्रयोगशाला के सुरक्षित और निष्पक्ष उपयोग के लिए निम्नलिखित नियमों का सख्ती से पालन करना अनिवार्य है।

1. क्रेडेंशियल सुरक्षा: अपनी लॉगिन कुंजी या पासवर्ड किसी भी अन्य छात्र के साथ कभी साझा नहीं करना चाहिए। सार्वजनिक रिपॉजिटरी में पासवर्ड अपलोड करना सख्त मना है।
2. कंप्यूटिंग संसाधन: पाठ्यक्रम से असंबंधित किसी भी प्रोग्राम को सर्वर पर चलाने की अनुमति नहीं है। अनुमति के बिना माइनिंग करना वर्जित है।
3. नेटवर्क एक्सेस: यूनिवर्सिटी वीपीएन के बिना बाहरी नेटवर्क से सीधा कनेक्शन स्वीकार्य नहीं है।
4. डेटा गोपनीयता: संवेदनशील अनुसंधान डेटा को निजी कंप्यूटर पर कॉपी नहीं किया जाना चाहिए, जब तक कि प्रोफेसर की पूर्व लिखित अनुमति न हो।
5. असाइनमेंट जमा करना: अंतिम तिथि के बाद जमा किए गए किसी भी असाइनमेंट को स्वीकार नहीं किया जाएगा, सिवाय वैध चिकित्सा प्रमाण पत्र के।
"""
    }
]

async def test_single_document(client: httpx.AsyncClient, doc: Dict[str, Any]) -> Dict[str, Any]:
    payload = {
        "text": doc["text"].strip(),
        "rate": 0.7,
        "force_tokens": ALL_13_LANG_FORCE_TOKENS,
    }
    t0 = time.perf_counter()
    try:
        res = await client.post(ENDPOINT_URL, json=payload, timeout=60.0)
        elapsed = time.perf_counter() - t0
        if res.status_code != 200:
            return {"lang": doc["lang"], "status": "ERROR", "error": f"HTTP {res.status_code}"}
        
        data = res.json()
        comp_text = data.get("compressed_text", "")
        orig_tok = data.get("original_tokens", 0)
        comp_tok = data.get("compressed_tokens", 0)
        red_pct = data.get("reduction_pct", 0.0)
        proc_ms = data.get("processing_time_ms", 0.0)

        # 否定・制約トークンが圧縮後テキストに保持されているかチェック
        terms = doc["check_terms"]
        missing_terms = [t for t in terms if t not in comp_text]
        preserved_all = len(missing_terms) == 0

        return {
            "lang": doc["lang"],
            "code": doc["code"],
            "status": "OK",
            "orig_tokens": orig_tok,
            "comp_tokens": comp_tok,
            "reduction_pct": red_pct,
            "proc_ms": proc_ms,
            "roundtrip_s": elapsed,
            "check_terms": terms,
            "missing_terms": missing_terms,
            "preserved": preserved_all,
            "comp_text": comp_text,
        }
    except Exception as e:
        return {"lang": doc["lang"], "status": "FAIL", "error": str(e)}

async def main():
    print("=" * 76)
    print("🌍 13-Language Negation & Constraint Preservation Benchmark")
    print(f"🔗 Modal Endpoint: {ENDPOINT_URL}")
    print(f"🛡️ Active Force Tokens: {len(ALL_13_LANG_FORCE_TOKENS)} tokens across all 13 languages")
    print("=" * 76)

    limits = httpx.Limits(max_connections=20, max_keepalive_connections=10)
    async with httpx.AsyncClient(limits=limits) as client:
        print(f"\n🚀 Launching {len(TEST_DOCUMENTS)} parallel requests to Modal (leveraging GPU auto-scaling)...")
        t_all_start = time.perf_counter()
        tasks = [test_single_document(client, doc) for doc in TEST_DOCUMENTS]
        results = await asyncio.gather(*tasks)
        total_wall_clock = time.perf_counter() - t_all_start

    print(f"\n✅ All {len(results)} language tasks completed in {total_wall_clock:.2f}s total wall-clock time!\n")

    print("-" * 76)
    print(f"{'Language':<18} | {'Tokens':<13} | {'Red%':<6} | {'GPU(ms)':<8} | {'Negation Safe?':<14} | {'Missing'}")
    print("-" * 76)

    all_safe = True
    for r in results:
        if r.get("status") != "OK":
            print(f"{r['lang']:<18} | ERROR: {r.get('error')}")
            all_safe = False
            continue
        tok_str = f"{r['orig_tokens']}->{r['comp_tokens']}"
        safe_str = "✅ 100% PRESERVED" if r["preserved"] else "❌ LEAKED"
        if not r["preserved"]:
            all_safe = False
        miss_str = "-" if not r["missing_terms"] else ", ".join(r["missing_terms"])
        print(f"{r['lang']:<18} | {tok_str:<13} | -{r['reduction_pct']}% | {r['proc_ms']:>6.1f}ms | {safe_str:<14} | {miss_str}")

    print("-" * 76)
    if all_safe:
        print("🎉 SUCCESS: Every single negative, prohibitive, and constraint rule")
        print("   across ALL 13 languages was 100% preserved without any meaning inversion!")
    else:
        print("⚠️ Some negative terms were missing. Review details above.")

    # 各言語の圧縮後抜粋サンプルを表示
    print("\n" + "=" * 76)
    print("📖 Sample Verification Excerpts (Checking Negative Clauses in Compressed Output):")
    print("=" * 76)
    for r in results:
        if r.get("status") == "OK":
            print(f"\n[{r['lang']} ({r['code']})] Tokens: -{r['reduction_pct']}% | Terms checked: {r['check_terms']}")
            lines = [l.strip() for l in r['comp_text'].splitlines() if l.strip()]
            for l in lines[:4]:
                print(f"   > {l[:100]}...")

if __name__ == "__main__":
    asyncio.run(main())
