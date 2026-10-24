import asyncio
import time
from typing import Dict, List, Any
import httpx

MODAL_URL = "https://shogo-toiyama--lefture-llmlingua2-llmlingua2api-compress.us-east.modal.run"

# 各言語のリアルなWebサイト・規約・ポリシー・シラバス文（TCPでもWikipediaでもない）
# 否定・禁止・免責・制約事項が自然に数多く含まれているリアルな文章
DOCUMENTS = {
    "English": {
        "source": "University Course Syllabus & Exam Policy",
        "text": """Course Policy and Exam Regulations:
Late assignments will not be accepted under any circumstances unless an official medical certificate is provided.
Students cannot collaborate on individual homework tasks; sharing code or solutions is strictly forbidden.
No electronic devices are permitted inside the examination hall without prior written permission from the instructor.
Never leave the examination room before the proctor collects all materials.
Except for designated group projects, all submitted work must be original, and plagiarized assignments will receive no credit.
Failure to comply with these rules will result in disciplinary action without exception.""",
        "key_negations": ["not", "unless", "cannot", "forbidden", "No", "without", "Never", "Except", "no credit", "without exception"]
    },
    "Japanese": {
        "source": "実在ホテルの宿泊約款およびキャンセル規約",
        "text": """当ホテルの宿泊約款およびキャンセル規約：
チェックイン予定時刻を連絡なく2時間を経過した場合は、予約を取り消されたものとみなします。
理由の如何に関わらず、前日以降のキャンセルについては返金を行いません。
客室内での喫煙は固く禁止されており、電子タバコであっても認められません。
事前の承認がない限り、宿泊登録者以外の立ち入りは一切不可といたします。
貴重品についての紛失や破損は、当ホテルに故意または重過失がない限り責任を負いかねます。
盲導犬などの介助犬を除き、ペットの同伴はお断りしております。""",
        "key_negations": ["なく", "行いません", "禁止", "認められません", "ない限り", "不可", "負いかねます", "除き", "お断り"]
    },
    "Chinese_Simplified": {
        "source": "大学实验室安全管理条例与考场守则",
        "text": """实验室安全管理条例与考场守则：
未经许可，任何人不得私自带出或借用实验室内部任何仪器设备。
实验室内严禁吸烟、饮食，禁止存放易燃易爆等危险品。
未经指导老师批准，严禁擅自启动高压设备或更改实验参数。
期末考试迟到超过15分钟者，一律不得入场，且本次考试成绩按零分处理。
除经特别批准的计算器外，严禁携带任何手机或通讯工具进入考场。
违规者将直接取消考试资格，且绝不给予补考机会。""",
        "key_negations": ["未经", "不得", "严禁", "禁止", "按零分处理", "除", "绝不", "取消"]
    },
    "Cantonese_Traditional": {
        "source": "香港某院校課程須知及退款約章",
        "text": """課程守則及退款約章：
未經校方書面批准，學員絕對唔准喺上堂期間錄音或錄影。
除非有公立醫院發出嘅醫生證明書，否則遲交功課一律冇得分。
開學之後，無論任何理由，學費均不設退款，亦唔可以轉讓畀其他人。
考試嗰陣，除咗筆同准考證之外，咪帶任何電子器材入試場。
若發現抄襲或作弊行為，該科成績即時作廢，絕無寬待。""",
        "key_negations": ["未經", "唔准", "除非", "冇得", "不設", "唔可以", "除咗", "咪帶", "絕無"]
    },
    "Korean": {
        "source": "대학교 수강 규정 및 과제 제출 지침",
        "text": """강의 수강 규정 및 과제 제출 지침：
사전 승인 없이는 어떠한 경우에도 과제의 지각 제출을 인정하지 않습니다.
지정된 기한 내에 제출하지 않은 과제는 0점 처리되며 재제출은 불가합니다.
담당 교수의 명시적인 허가 없이 생성형 AI나 외부 솔루션을 무단 활용하는 것은 엄격히 금지됩니다.
출석 일수의 4분의 1 이상 결석한 학생은 시험 응시 자격이 주어지지 않으며 F 학점을 부여합니다.
정당한 사유가 없는 한 추가 과제나 대체 평가는 일절 제공되지 않습니다.""",
        "key_negations": ["없이는", "인정하지 않습니다", "제출하지 않은", "불가합니다", "없이", "금지됩니다", "주어지지 않으며", "없는 한", "제공되지 않습니다"]
    },
    "French": {
        "source": "Conditions Générales de Vente et de Transport (SNCF/RATP)",
        "text": """Conditions Générales de Vente et Réglementation du Transport :
Tout voyageur sans titre de transport valide n'est pas autorisé à monter à bord du train.
Les billets promotionnels ne sont ni échangeables ni remboursables sous aucun prétexte.
Il est strictement interdit de fumer ou de vapoter dans l'ensemble des rames et des gares.
Aucun bagage ne doit être laissé sans surveillance sous peine de destruction immédiate par les services de sécurité.
Sauf accord préalable et express, les animaux de grande taille ne sont pas admis dans les compartiments de voyage.
Aucune contestation ne sera prise en compte après un délai de 30 jours suivant la date du voyage.""",
        "key_negations": ["sans", "n'est pas", "ne sont ni", "ni", "aucun", "interdit", "Aucun", "sans", "Sauf", "ne sont pas", "Aucune", "ne sera"]
    },
    "Spanish": {
        "source": "Reglamento Académico y de Exámenes Universitarios",
        "text": """Reglamento Académico y de Evaluación Oficial :
No se aceptará ninguna entrega fuera de plazo sin una justificación médica oficial debidamente validada.
Queda terminantemente prohibido el uso de teléfonos móviles durante el transcurso de las pruebas evaluativas.
Ningún estudiante podrá abandonar el aula sin la autorización expresa del profesor responsable.
Los plagios detectados supondrán automáticamente la calificación de suspenso, sin posibilidad de recuperación extraordinaria.
Salvo indicación contraria en la guía docente, los exámenes son individuales y nunca se permitirá la colaboración entre pares.
Nadie podrá presentarse a la convocatoria extraordinaria sin haber cumplido el mínimo de asistencia.""",
        "key_negations": ["No", "ninguna", "sin", "prohibido", "Ningún", "sin", "sin posibilidad", "Salvo", "nunca", "Nadie", "sin"]
    },
    "Portuguese": {
        "source": "Termos de Uso e Política de Cancelamento de Viagens",
        "text": """Termos de Uso e Regulamento de Viagens e Hospedagem :
Não é permitido o cancelamento com reembolso integral a menos de 48 horas do check-in.
Nenhum passageiro poderá embarcar sem documento de identidade oficial com foto em mãos.
É estritamente proibido fumar em qualquer dependência do hotel ou nas áreas fechadas.
Sem o pagamento prévio da taxa de reserva, a vaga não será garantida sob nenhuma hipótese.
Exceto em casos fortuitos ou de força maior comprovados, a ausência será considerada desistência sem direito a reembolso.
Nunca forneça suas credenciais ou senhas de acesso a terceiros não autorizados.""",
        "key_negations": ["Não", "Nenhum", "sem", "proibido", "Sem", "não será", "nenhuma", "Exceto", "sem direito", "Nunca", "não"]
    },
    "German": {
        "source": "Allgemeine Geschäfts- und Prüfungsbedingungen (Hochschule/Bahn)",
        "text": """Allgemeine Prüfungsordnung und Richtlinien :
Verspätet eingereichte Arbeiten werden unter keinen Umständen zur Bewertung angenommen.
Ohne vorherige schriftliche Genehmigung des Prüfungsausschusses ist kein Rücktritt von der Prüfung möglich.
Während der Klausur ist die Verwendung von internetfähigen Geräten strikt untersagt.
Niemand darf den Prüfungsraum vor Ablauf der ersten Stunde verlassen, außer im akuten medizinischen Notfall.
Keine Rückerstattung der Gebühren erfolgt bei unentschuldigtem Fernbleiben vom Termin.
Täuschungsversuche führen ohne Ausnahme zum sofortigen Ausschluss und Nichtbestehen der gesamten Veranstaltung.""",
        "key_negations": ["unter keinen", "nicht", "Ohne", "kein", "untersagt", "Niemand", "außer", "Keine", "ohne Ausnahme", "Nichtbestehen"]
    },
    "Italian": {
        "source": "Regolamento Didattico e Condizioni di Trasporto Pubblico",
        "text": """Regolamento Didattico d'Ateneo e Norme d'Esame :
Non è consentita in nessun caso la consegna posticipata degli elaborati senza idonea certificazione medica.
Nessun rimborso sarà riconosciuto in caso di rinuncia agli studi oltre il termine prescritto.
È severamente vietato introdurre dispositivi elettronici non preventivamente autorizzati dal docente.
I candidati non possono allontanarsi dall'aula d'esame senza l'esplicito permesso della commissione.
Salvo diversa disposizione della segreteria, i crediti acquisiti non sono trasferibili senza esame preventivo.
Nessuna eccezione sarà accordata a studenti privi dei requisiti di frequenza minima obbligatoria.""",
        "key_negations": ["Non", "nessun", "senza", "Nessun", "vietato", "non possono", "senza", "Salvo", "non sono", "senza", "Nessuna"]
    },
    "Russian": {
        "source": "Правила внутреннего распорядка и сдачи экзаменов",
        "text": """Правила внутреннего распорядка и проведения экзаменационной сессии :
Студенты не допускаются к сдаче экзамена без предъявления зачетной книжки или студенческого билета.
Опоздания на лекции и практические занятия категорически не приветствуются и не являются уважительной причиной.
Во время проведения тестирования строго запрещено использование мобильных устройств и наушников.
Никакие апелляции не принимаются по истечении трех рабочих дней после публикации результатов.
Без предварительного согласования с деканатом пропуск занятий считается прогулом без уважительной причины.
Кроме случаев внезапного заболевания, перенос даты экзамена не разрешается.""",
        "key_negations": ["не", "без", "не являются", "запрещено", "Никакие", "не принимаются", "Без", "без", "Кроме", "не разрешается"]
    },
    "Arabic": {
        "source": "لوائح الامتحانات الجامعية وسياسة الاسترداد",
        "text": """لوائح الامتحانات وسياسات القبول والتسجيل :
لا يُسمح لأي طالب بدخول قاعة الامتحان بدون إبراز البطاقة الجامعية سارية المفعول.
لن يتم قبول أي أعذار للتأخر عن موعد تسليم الأبحاث ما لم تكن معتمدة من الإدارة الطبية.
يُحظر تماماً استخدام الهواتف المحمولة أو أي أجهزة ذكية داخل لجان الاختبارات.
لا يحق لأي مشترك استرداد الرسوم المدفوعة بعد بدء الفصل الدراسي بدون استثناء.
إلا في الحالات الطارئة القصوى، لن يُعاد عقد الامتحان لأي متغيب مهما كانت الأسباب.
يُعتبر أي تواصل بين الطلاب غشاً صريحاً ولا تساهل فيه على الإطلاق.""",
        "key_negations": ["لا يُسمح", "بدون", "لن يتم", "ما لم", "يُحظر", "لا يحق", "بدون استثناء", "إلا", "لن يُعاد", "ولا تساهل"]
    },
    "Hindi": {
        "source": "विश्वविद्यालय परीक्षा नियम एवं सामान्य दिशानिर्देश",
        "text": """परीक्षा नियमावली एवं छात्रों हेतु आवश्यक निर्देश :
बिना वैध पहचान पत्र के किसी भी परीक्षार्थी को परीक्षा कक्ष में प्रवेश की अनुमति नहीं दी जाएगी।
परीक्षा केंद्र में मोबाइल फोन, स्मार्टवॉच अथवा अन्य इलेक्ट्रॉनिक उपकरण ले जाना सख्त मना है।
अंतिम तिथि के बाद जमा किए गए किसी भी असाइनमेंट को स्वीकार नहीं किया जाएगा।
पर्यवेक्षक की अनुमति के बिना कोई भी छात्र अपनी सीट से नहीं उठ सकता है।
नकल या अनुचित साधनों का प्रयोग करने वाले छात्र की परीक्षा तुरंत रद्द कर दी जाएगी और कोई छूट नहीं मिलेगी।
चिकित्सा प्रमाण पत्र के अलावा किसी अन्य आधार पर पुनः परीक्षा का अवसर नहीं दिया जाएगा।""",
        "key_negations": ["बिना", "नहीं दी जाएगी", "मना है", "नहीं किया जाएगा", "के बिना", "नहीं उठ सकता", "कोई छूट नहीं", "के अलावा", "नहीं दिया जाएगा"]
    }
}


async def test_single_document(client: httpx.AsyncClient, lang: str, info: Dict[str, Any], rate: float):
    text = info["text"]
    t0 = time.perf_counter()
    resp = await client.post(
        MODAL_URL,
        json={"text": text, "rate": rate},
        timeout=60.0
    )
    elapsed = time.perf_counter() - t0
    if resp.status_code != 200:
        return {
            "lang": lang,
            "status": "error",
            "error": resp.text,
            "time_s": elapsed
        }
    
    data = resp.json()
    comp_text = data.get("compressed_text", "")
    orig_chars = data.get("original_chars", len(text))
    comp_chars = data.get("compressed_chars", len(comp_text))
    reduction_pct = data.get("reduction_pct", 0.0)

    # 否定語の残存チェック
    preserved_negations = []
    dropped_negations = []
    for neg in info["key_negations"]:
        # 単語またはその一部が含まれているか
        if neg in comp_text:
            preserved_negations.append(neg)
        else:
            # 大文字小文字の差異や複合語の分割チェック
            if any(part in comp_text for part in neg.split()):
                preserved_negations.append(neg)
            else:
                dropped_negations.append(neg)
    
    return {
        "lang": lang,
        "source": info["source"],
        "rate": rate,
        "status": "ok",
        "time_s": round(elapsed, 2),
        "orig_chars": orig_chars,
        "comp_chars": comp_chars,
        "reduction_pct": reduction_pct,
        "preserved_negations": preserved_negations,
        "dropped_negations": dropped_negations,
        "negation_preservation_rate": round(len(preserved_negations) / max(1, len(info["key_negations"])) * 100, 1),
        "original_text": text,
        "compressed_text": comp_text
    }


async def main():
    print("=" * 80)
    print("🌍 13言語 リアル規約・シラバス・約款文書 否定語・禁止事項保持ベンチマーク (10 GPU 並列)")
    print("=" * 80)

    async with httpx.AsyncClient() as client:
        # Rate 0.7 で 13言語を同時並行（Modal 10GPU並列を活用）
        print("\n🚀 [1/2] 圧縮率 0.7 (約20-30%カット) を 13 言語同時に並列実行中...")
        t_batch_07 = time.perf_counter()
        tasks_07 = [
            test_single_document(client, lang, info, rate=0.7)
            for lang, info in DOCUMENTS.items()
        ]
        results_07 = await asyncio.gather(*tasks_07)
        total_time_07 = time.perf_counter() - t_batch_07
        print(f"✨ 13言語並列処理完了: {total_time_07:.2f} 秒\n")

        # 結果表示
        for r in results_07:
            if r["status"] == "error":
                print(f"❌ [{r['lang']}] Error: {r['error']}")
                continue
            badge = "✅ 100% 保持" if not r["dropped_negations"] else f"⚠️ 欠落あり: {r['dropped_negations']}"
            print(f"[{r['lang']}] ({r['source']})")
            print(f"   ⏱️ 実行時間: {r['time_s']}s | 削減率: -{r['reduction_pct']}% ({r['orig_chars']}文字 -> {r['comp_chars']}文字)")
            print(f"   🛡️ 否定・制約語保持率: {r['negation_preservation_rate']}% ({len(r['preserved_negations'])}/{len(r['preserved_negations']) + len(r['dropped_negations'])}) -> {badge}")
            if r["dropped_negations"]:
                print(f"   ⚠️ 落ちた語: {r['dropped_negations']}")
            print("   --- 圧縮後抜粋 ---")
            for line in r["compressed_text"].splitlines()[:3]:
                if line.strip():
                    print(f"   {line.strip()[:100]}...")
            print()

        # Rate 0.6 で 13言語を同時並行
        print("\n🚀 [2/2] 圧縮率 0.6 (約30-40%カット) を 13 言語同時に並列実行中...")
        t_batch_06 = time.perf_counter()
        tasks_06 = [
            test_single_document(client, lang, info, rate=0.6)
            for lang, info in DOCUMENTS.items()
        ]
        results_06 = await asyncio.gather(*tasks_06)
        total_time_06 = time.perf_counter() - t_batch_06
        print(f"✨ 13言語並列処理完了: {total_time_06:.2f} 秒\n")

        # 結果表示
        for r in results_06:
            if r["status"] == "error":
                print(f"❌ [{r['lang']}] Error: {r['error']}")
                continue
            badge = "✅ 100% 保持" if not r["dropped_negations"] else f"⚠️ 欠落あり: {r['dropped_negations']}"
            print(f"[{r['lang']}] ({r['source']})")
            print(f"   ⏱️ 実行時間: {r['time_s']}s | 削減率: -{r['reduction_pct']}% ({r['orig_chars']}文字 -> {r['comp_chars']}文字)")
            print(f"   🛡️ 否定・制約語保持率: {r['negation_preservation_rate']}% ({len(r['preserved_negations'])}/{len(r['preserved_negations']) + len(r['dropped_negations'])}) -> {badge}")
            if r["dropped_negations"]:
                print(f"   ⚠️ 落ちた語: {r['dropped_negations']}")
            print("   --- 圧縮後抜粋 ---")
            for line in r["compressed_text"].splitlines()[:3]:
                if line.strip():
                    print(f"   {line.strip()[:100]}...")
            print()


if __name__ == "__main__":
    asyncio.run(main())
