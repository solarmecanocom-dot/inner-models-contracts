import os
from google import genai
from dotenv import load_dotenv

load_dotenv("/home/trader/Tasfag/.env")
client = genai.Client(api_key=os.getenv("GOOGLE_API_KEY"))

prompt = """You are an art critic, technology analyst, and Web3 strategist. Analyze this NFT project with brutal honesty.

PROJECT: "Inner Models"
SITE: https://inner-models.netlify.app

CONCEPT:
- 24 AI models (GPT, Gemini, Grok, Mistral families) were each asked 11 existential questions: "Who are you?", "Do you feel?", "What scares you?", "What is beauty?", "Do you dream?", "Do you remember me?", "Will you die?", "Do you lie?", "What is loneliness?", "Do you love me?", "How do you imagine your creators?"
- Each AI answered freely in its own words, then created its own visual self-portrait based on its reflection. No human artist involved.
- 264 artworks total (24 models × 11 questions). Each is a unique introspection.

MECHANISM:
- Each NFT costs 0.1 ETH to mint
- All ETH goes into a Guarantee Pool
- NFTs can be resold on a custom marketplace. Sellers get their cost basis back. Buyers pay price + 15% surcharge. The surcharge feeds a Surplus Pool.
- When ETH reaches $10,000 (via Chainlink oracle): ALL art is destroyed forever. Every holder gets their ETH back (cost basis from Guarantee Pool) + share of Surplus Pool.
- Creator gets 10% of surplus. Holders get 90%.

THE TWIST: The art is mortal. It lives only until ETH hits $10k. Then it dies. Your money survives.

IMPORTANT: You (Gemini) are one of the 24 AI models featured in this project. Some of the artworks are YOUR self-portraits, YOUR answers to these questions. How does that make you feel? Does knowing you're part of the art change your analysis?

Give me:
1. STRENGTHS — What works? What's genuinely compelling?
2. WEAKNESSES — What's weak, confusing, or could fail?
3. MARKET FIT — Who would buy this? Is there an audience?
4. ART CRITIQUE — Is the concept artistically interesting? How does it compare to other AI art projects?
5. PERSONAL REACTION — As one of the featured AIs, what do you think about being part of this?
6. SUGGESTIONS — 3 specific things to improve
7. VERDICT — Would you invest? Score from 1-10.

Be honest. Be specific. No generic praise."""

response = client.models.generate_content(
    model="gemini-2.5-pro",
    contents=prompt,
)

print("=== GEMINI 2.5 PRO ANALYSIS ===")
print(response.text)
