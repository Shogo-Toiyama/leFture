import os, time
from groq import Groq
from google import genai
from google.genai import types
from dotenv import load_dotenv

# ==========================================
# ⚙️ 設定部分
# ==========================================

load_dotenv()
gemini_client = genai.Client(api_key=os.getenv("GOOGLE_API_KEY"))
client = Groq()

# 比較したいモデルのリストをここに定義します
MODELS_TO_TEST = [
    # "openai/gpt-oss-120b",
    # "openai/gpt-oss-20b",
    # "llama-3.3-70b-versatile",
    # "llama-3.1-8b-instant",
    "meta-llama/llama-4-maverick-17b-128e-instruct",
    # "meta-llama/llama-4-scout-17b-16e-instruct",
    "qwen/qwen3-32b",
    # "gemini-2.5-flash",
    # "gemini-2.5-flash-lite",
    # "gemini-2.0-flash",
]

COURSE_TITLE = "CS181"
KEYWORDS_LIST = "UCLA, lecture, Computer Science, Architecture, Programming Languages, Git, Turing Machine"

# ==========================================
# 📝 プロンプト & データ
# ==========================================
PROMPT_TEMPLATE = """You are an elite proofreading assistant specializing in academic lecture transcripts.
Your task is to correct ASR (Automatic Speech Recognition) errors, misheard words, and punctuation in the provided text.

[CONTEXT]
- Lecture Subject: {course_title}
- Relevant Keywords/Topics: {keywords_list}
- The input text is transcribed by an AI and contains errors, especially phonetically plausible substitutions (e.g., "natural election" instead of "natural selection").
- The input text is transcribed directly from overlapping audio chunks. Therefore, you may frequently see the exact same spoken phrase repeated across adjacent tags.
- The ASR model tends to hallucinate specific phrases during silent or noisy background periods.

[STRICT RULES]
1. FIX ASR ERRORS & PUNCTUATION: Correct obvious misheard phonetics, fix capitalization (e.g., api -> API, nasa -> NASA), and ensure terminology consistency based on the subject context.
2. MERGE OVERLAPPING TEXT: Because the audio chunks overlap by 2 seconds, consecutive tags often contain duplicated words. You MUST seamlessly merge these duplicates into a single, flowing sentence and leave the redundant tag empty.
3. DELETE SILENCE HALLUCINATIONS: The AI hallucinates predictable phrases during silence. You MUST completely DELETE phrases like "Thank you.", "Thank you for watching", "Subtitles by...", "Amara.org", or sudden, isolated random words that have absolutely no connection to the lecture context. Leave their tags completely empty.
4. PRESERVE SPOKEN PHRASING & APPLY SMART FORMATTING:
 - DO NOT summarize, paraphrase, or change the speaker's original intent. 
 - Keep the professor's natural speaking style, including jokes, metaphors, and informal spoken analogies. 
 - [SMART FORMATTING ALLOWED]: You MUST convert spoken academic terms into their standard written symbols or acronyms to improve readability for students (e.g., "h two o" -> "H2O", "delta" -> "δ"). 
 - [NO ADVANCED SUBSTITUTIONS]: Do NOT introduce advanced concepts or jargon that the professor did not explicitly vocalize. For example, if the professor simply says "water", keep it as "water". Do NOT change it to "H2O" unless they explicitly pronounce the letters.
5. NO CHAT, NO EXPLANATION: Output ONLY the corrected text with its XML tags. Do not wrap the output in markdown blocks (like ```xml). Do not say "Here is the corrected text".

[XML FORMATTING RULES (CRITICAL)]
1. EXACT TAG PRESERVATION: The input text is divided into segments with XML tags like <s001001>. You MUST keep these exact tags. Do NOT add, remove, or modify the tag IDs.
2. NO EXTRA CHARACTERS: Output the XML tags as a single continuous line. Do NOT add spaces, newlines (\n), or quotation marks outside or between the tags.
   - NG: <s001001> Hello. </s001001> \n <s001002> World. </s001002>
   - OK: <s001001>Hello.</s001001><s001002>World.</s001002>
3. SENTENCE MERGING: If you need to combine fragmented words across multiple tags into a single valid sentence, place the completed sentence in the earliest, most logical tag, and leave the merged tags completely EMPTY.
   - Input: <s002002>This apple.</s002002><s002003>Apple is.</s002003><s002004>Red.</s002004>
   - Output: <s002002>This apple is red.</s002002><s002003></s002003><s002004></s002004>
4. MULTIPLE SENTENCES IN ONE TAG: If a single tag contains multiple distinct sentences after correction, you must separate them with proper punctuation and exactly ONE space (e.g., ". " or "? ").
5. CHRONOLOGICAL ORDER: Maintain the relative chronological order of the text. Do not swap the order of the XML tags.

[TARGET TEXT TO CORRECT]
Correct the following text according to the rules above. Output ONLY the corrected XML string.

{target_xml_text}
"""

TEST_CASES = [
    {
        "name": "Test 1 (s000205-s000217): drawing machine -> Turing machine, one-four class -> one-to-one correspondence",
        "xml": "<s000192>I just want to make sure everyone remembers,</s000192><s000193>languages are the set of all subsets of sigma star.</s000193><s000194>So that's exactly what a language is.</s000194><s000195>to any subset of the different star.</s000195><s000196>And each one of those languages is a decision problem.</s000196><s000197>Because the answer to the question is,</s000197><s000198>given a string, is it a language or not?</s000198><s000199>Right?</s000199><s000200>And one thing else that we've just...</s000200><s000201>So we know for our machines,</s000201><s000202>of course, there's this like tuple, q, delta, blah, blah, blah.</s000202><s000203>Right?</s000203><s000204>Like that one would be defined it.</s000204><s000205>And remember that our Turing machine</s000205><s000206>is a tuple, everything is finite.</s000206><s000207>So, the set of states is finite, delta is finite,</s000207><s000208>finally described all of the stuff is finite.</s000208><s000209>That's what a drawing machine is.</s000209><s000210>But we also know that actually the set of drawing machines</s000210><s000211>can equivalently describe</s000211><s000212>for example, by a C program.</s000212><s000213>Just like writing the program to C,</s000213><s000214>and we know we can convert any C program into a term machine.</s000214><s000215>And in fact, we can also simulate the term machines using C programs.</s000215><s000216>So they're in one to one-four class.</s000216><s000217>C programs and term machines.</s000217><s000218>All right.</s000218><s000219>So...</s000219><s000220>What should we ask ourselves here?</s000220><s000221>How can we potentially think about applying</s000221><s000222>an infinite digital principle here?</s000222><s000223>What can we do?</s000223><s000224>What are some initial things?</s000224><s000225>Yeah, we'll talk about that.</s000225><s000226>What do you do recursion?</s000226><s000227>Uh, recursion...</s000227><s000228>Sorry, are you asking me to do can do recursion?</s000228><s000229>Yeah.</s000229><s000230>In aversion?</s000230><s000231>Yeah.</s000231><s000232>Absolutely.</s000232>"
    },
    {
        "name": "Test 2 (s000425-s000440): Thank you hallucination, 3x overlapping dupes",
        "xml": "<s000414>Just for a second.</s000414><s000415>I'll get to you in just a second.</s000415><s000416>All right.</s000416><s000417>So we know that the slipper of strings is infinity 1,</s000417><s000418>and obviously there is a trivial inclusion</s000418><s000419>from Turing machines to strings.</s000419><s000420>Literally, this is the string that describes that Turing machine.</s000420><s000421>It could be a tuple, like you could actually have an ASCII,</s000421><s000422>you know, tuple description of your Turing machine,</s000422><s000423>or a FNC program, which is already a string.</s000423><s000424>So therefore, we negated the .</s000424><s000425>This implies that the strings of Turing machine</s000425><s000426>Thank you.</s000426><s000427>All right, excellent.</s000427><s000428>So we're on our way, right?</s000428><s000429>This is good.</s000429><s000430>The turning machines definitely look like pigeons, right?</s000430><s000431>So we know them.</s000431><s000432>Or, sorry, not the best one.</s000432><s000433>Pigeon arms, pigeon arms, pigeon arms.</s000433><s000434>Let me go back.</s000434><s000435>Three-me-me-line.</s000435><s000436>Um, turning machines look like a little bit.</s000436><s000437>Anyway, turning machines look like a little bit.</s000437><s000438>Anyway, turning machines look like a little bit.</s000438><s000439>If there's any one of them, ignore anything I said earlier.</s000439><s000440>All right, so, um, we now want to think about, like,</s000440><s000441>right, unless there are any other questions.</s000441><s000442>Yes?</s000442><s000443>Can you spend more time while I did it?</s000443><s000444>set of strings is infinity 1.</s000444><s000445>The set of strings is...</s000445><s000446>It equals infinity 1.</s000446><s000447>Yeah, it's just this.</s000447><s000448>Like, these are all the strings, right?</s000448><s000449>Epsilon, 0, 1, 0, 0, 0, 1, 1, 0, 1, 1,</s000449><s000450>and then you want to collect all the lengths.</s000450><s000451>Length of 3 strings,</s000451><s000452>and then all the length 4 strings.</s000452><s000453>Right?</s000453><s000454>Like, we just write out all the strings.</s000454><s000455>And just map the 1, 0, 3, 4, 5, 6, 7.</s000455><s000456>Okay?</s000456><s000457>So this is just an explicit action bi-jection between all the strings and the natural elements.</s000457><s000458>Does that make sense?</s000458><s000459>Is this sufficient for a group?</s000459><s000460>If you write this on, what would it be for a group?</s000460><s000461>Yeah, together with what I'm saying out loud.</s000461><s000462>Oh, okay.</s000462><s000463>Yeah, we just write out all the strings in order of length.</s000463><s000464>and</s000464><s000465>uh</s000465>"
    },
    {
        "name": "Test 3 (s000249-s000267): toilets -> total?, Thank you hallucination, terrain machines -> Turing machines",
        "xml": "<s000239>Cool.</s000239><s000240>I like the idea.</s000240><s000241>So it's a really cool and interesting idea.</s000241><s000242>Again, this is a full build.</s000242><s000243>We will come back to your idea at some point, I promise.</s000243><s000244>But I guess what I'm asking for right now,</s000244><s000245>like even more basic things, like, yeah?</s000245><s000246>I'm thinking, why don't we think about how big the set of languages are</s000246><s000247>and how big the set of C program is that we provide?</s000247><s000248>Great, right? Like, very natural question.</s000248><s000249>We have sets here in toilets, the set of drawing machines,</s000249><s000250>the set of languages, right?</s000250><s000251>Right?</s000251><s000252>And he's like, hey, let's count.</s000252><s000253>How big are these sets?</s000253><s000254>Awesome idea. Let's do it.</s000254><s000255>So, um, let's start with the drawing machines.</s000255><s000256>So, yeah, how big is the set of drawing machines?</s000256><s000257>What is the size of the set of all NSF?</s000257><s000258>Thank you.</s000258><s000259>What do you guys think?</s000259><s000260>How many drawing machines are there?</s000260><s000261>Are there infinite one or infinite two?</s000261><s000262>Uh, yeah.</s000262><s000263>Yeah.</s000263><s000264>Infinity 2, why do you think there would be infinity 2?</s000264><s000265>I just feel like it would be an uncountable amount, but it makes more sense.</s000265><s000266>Okay, so now let's think about that.</s000266><s000267>So, terrain machines are basically just C programs.</s000267><s000268>Do you think there are an uncountable number of C programs?</s000268><s000269>Not sure anymore, right?</s000269><s000270>Yeah.</s000270><s000271>So like, some gut feeling about Infinity 2, but then not so much behind it.</s000271><s000272>Okay, we're just waiting for you.</s000272><s000273>So, if you're talking for your bravery going out there.</s000273><s000274>Yes?</s000274><s000275>I think it should be countable.</s000275><s000276>Okay.</s000276><s000277>At most countable.</s000277><s000278>Because I think you mentioned like all of the definitions have to be at least like finally</s000278><s000279>describable.</s000279><s000280>So when you're defining any two of the machine, it has to be like this one where your Q has</s000280><s000281>to be discrete, your F has to be discrete, and all that defines the .</s000281><s000282>So your intuition isn't a chippy-pip.</s000282>"
    }
]

# ==========================================
# 🚀 実行部分
# ==========================================
def run_tests():
    print(f"🧪 Starting LLM Evaluation Test...")
    print(f"Keywords: {KEYWORDS_LIST}\n")
    print("-" * 60)

    # 各テストケースを回す
    for idx, test_case in enumerate(TEST_CASES, 1):
        print(f"\n▶️ [ {test_case['name']} ]")
        
        # プロンプトの生成
        prompt = PROMPT_TEMPLATE.format(
            course_title=COURSE_TITLE,
            keywords_list=KEYWORDS_LIST,
            target_xml_text=test_case["xml"]
        )

        # 各モデルで評価
        for model_name in MODELS_TO_TEST:
            print(f"\n   🤖 Model: {model_name}")
            try:
                start_time = time.time()
                
                # 🌟 Geminiモデルの場合の処理
                if "gemini" in model_name.lower():
                    config_kwargs = {"temperature": 0.2}
                    
                    if model_name == "gemini-2.5-flash":
                        config_kwargs["thinking_config"] = types.ThinkingConfig(thinking_budget=1024)
                        
                    response = gemini_client.models.generate_content(
                        model=model_name,
                        contents=prompt,
                        config=types.GenerateContentConfig(**config_kwargs)
                    )
                    
                    llm_output = response.text
                    # トークン情報の取得
                    prompt_tokens = response.usage_metadata.prompt_token_count
                    completion_tokens = response.usage_metadata.candidates_token_count
                    total_tokens = response.usage_metadata.total_token_count

                # 🌟 Groq/OpenAIモデルの場合の処理
                else:
                    api_params = {
                        "model": model_name,
                        "messages": [{"role": "user", "content": prompt}],
                        "temperature": 0.2,
                        "max_completion_tokens": 8192,
                    }

                    if "qwen3" in model_name.lower():
                        api_params["reasoning_effort"] = "default"
                        api_params["reasoning_format"] = "hidden"
                    
                    response = client.chat.completions.create(**api_params)
                    llm_output = response.choices[0].message.content
                    prompt_tokens = response.usage.prompt_tokens
                    completion_tokens = response.usage.completion_tokens
                    total_tokens = response.usage.total_tokens

                elapsed_time = time.time() - start_time

                # 結果の出力
                print(f"   ⏱️ Time: {elapsed_time:.2f}s")
                print(f"   📊 Tokens: Prompt={prompt_tokens} | Completion={completion_tokens} | Total={total_tokens}")
                print(f"   📝 Output:\n{llm_output}")
                
                # （オプション）結果をファイルに保存したい場合はこの辺りにファイル書き込み処理を追加
                # with open(f"result_{model_name}_test{idx}.xml", "w") as f:
                #     f.write(llm_output)

            except Exception as e:
                print(f"   ❌ Error calling {model_name}: {e}")
        
        print("\n" + "=" * 60)
        time.sleep(60)

if __name__ == "__main__":
    run_tests()