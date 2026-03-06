
import os
from dotenv import load_dotenv
from groq import Groq


load_dotenv()

client = Groq()
filename = "./audio_noisereduce.wav"

with open(filename, "rb") as file:
    transcription = client.audio.transcriptions.create(
      file=(filename, file.read()),
      model="whisper-large-v3-turbo",
      temperature=0.1,
      response_format="verbose_json",
      language="en",
      prompt="UCLA, lecture, Computer Science, Architecture, Programming Languages, Git, Turing Machine",
    )
    print(transcription.text)
    # print(dir(transcription))
      