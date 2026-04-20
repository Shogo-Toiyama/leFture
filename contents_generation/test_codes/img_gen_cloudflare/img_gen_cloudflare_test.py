import os, requests
import base64
from dotenv import load_dotenv

load_dotenv()
ACCOUNT_ID = os.getenv("CLOUDFLARE_ACCOUNT_ID")
API_TOKEN = os.getenv("CLOUDFLARE_API_KEY")

MODEL = "flux-1"
# MODEL = "SDXL-Lightning"
# MODEL = "SDXL-Base"

def generate_and_save_image():
    match MODEL:
        case "flux-1":
            url = f"https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/ai/run/@cf/black-forest-labs/flux-1-schnell"
        case "SDXL-Lightning":
            url = f"https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/ai/run/@cf/bytedance/stable-diffusion-xl-lightning"
        case "SDXL-Base":
            url = f"https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/ai/run/@cf/stabilityai/stable-diffusion-xl-base-1.0"
    
    headers = {
        "Authorization": f"Bearer {API_TOKEN}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "prompt": "Japanese Instant Miso Ramen with thick noodles, rich broth, and a perfectly boiled egg on top. The word “ramen” is engraved on the side of the bowl.",
        "width": 512,
        "height": 512,
        # "width": 1024,
        # "height": 1024,
        "num_steps": 4,
        # "guidance": 1.0
    }

    print("画像生成中...")
    response = requests.post(url, headers=headers, json=payload)

    if response.ok:
        content_type = response.headers.get("Content-Type", "")
        
        # パターン1: JSONで返ってきた場合 (Fluxなど)
        if "application/json" in content_type:
            data = response.json() # ✅ JSONだと分かってからパースする
            if data.get("success"):
                image_bytes = base64.b64decode(data["result"]["image"])
                match MODEL:
                    case "flux-1":
                        with open ("flux-1.jpg", "wb") as f:
                            f.write(image_bytes)
                    case "SDXL-Lightning":
                        with open("sdxl-lightning.jpg", "wb") as f:
                            f.write(image_bytes)
                    case "SDXL-Base":
                        with open("sdxl-base.jpg", "wb") as f:
                            f.write(image_bytes)
                print("大成功！🚀 (JSONから画像を復元しました)")
            else:
                print("APIエラー:", data)
                
        # パターン2: 画像データが直接返ってきた場合 (SDXLなど)
        elif "image/" in content_type:
            # response.content に生の中身（バイナリ）が入っている
            match MODEL:
                    case "flux-1":
                        with open ("flux-1.jpg", "wb") as f:
                            f.write(response.content)
                    case "SDXL-Lightning":
                        with open("sdxl-lightning.jpg", "wb") as f:
                            f.write(response.content)
                    case "SDXL-Base":
                        with open("sdxl-base.jpg", "wb") as f:
                            f.write(response.content)
            print("大成功！🚀 (直接画像データを受信しました)")
            
        else:
            print("未知のレスポンス形式です:", content_type)
    else:
        # 認証エラーやURLミスなどの場合
        print(f"通信エラー発生! ステータスコード: {response.status_code}")
        # エラー時もJSONではないテキストが返ってくることがあるため対応
        try:
            print("エラー内容:", response.json())
        except requests.exceptions.JSONDecodeError:
            print("エラー内容:", response.text)

if __name__ == "__main__":
    generate_and_save_image()