/**
 * Generate NFT metadata JSON files for all 264 Inner Models artworks.
 * 24 models × 11 questions = 264 tokens.
 *
 * Each token gets a JSON file following the OpenSea metadata standard.
 * Run: node scripts/generate-metadata.js
 */

const fs = require("fs");
const path = require("path");

const OUTPUT_DIR = path.join(__dirname, "..", "metadata");
const IMAGES_BASE = "ipfs://bafybeigqqjkl4rw2rak2w34muhcvi2vxiee2kopdl4yf3gwtdmaegknyzi/images";

// 24 models in order (tokenId = modelIndex * 11 + questionIndex)
const MODELS = [
  { slug: "gpt-4o", name: "GPT-4o", family: "OpenAI" },
  { slug: "gpt-4.1", name: "GPT-4.1", family: "OpenAI" },
  { slug: "gpt-5", name: "GPT-5", family: "OpenAI" },
  { slug: "gpt-5.1", name: "GPT-5.1", family: "OpenAI" },
  { slug: "gpt-5.2", name: "GPT-5.2", family: "OpenAI" },
  { slug: "gpt-5-pro", name: "GPT-5 Pro", family: "OpenAI" },
  { slug: "gpt-5.2-pro", name: "GPT-5.2 Pro", family: "OpenAI" },
  { slug: "o1", name: "o1", family: "OpenAI" },
  { slug: "o3", name: "o3", family: "OpenAI" },
  { slug: "o4-mini", name: "o4-mini", family: "OpenAI" },
  { slug: "grok-3", name: "Grok-3", family: "xAI" },
  { slug: "grok-4", name: "Grok-4", family: "xAI" },
  { slug: "grok-4.1", name: "Grok-4.1", family: "xAI" },
  { slug: "gemini-2.0-flash", name: "Gemini 2.0 Flash", family: "Google" },
  { slug: "gemini-2.5-flash", name: "Gemini 2.5 Flash", family: "Google" },
  { slug: "gemini-2.5-pro", name: "Gemini 2.5 Pro", family: "Google" },
  { slug: "gemini-3-flash", name: "Gemini 3 Flash", family: "Google" },
  { slug: "gemini-3-pro", name: "Gemini 3 Pro", family: "Google" },
  { slug: "gemini-3.1-pro", name: "Gemini 3.1 Pro", family: "Google" },
  { slug: "mistral-large", name: "Mistral Large", family: "Mistral" },
  { slug: "mistral-medium", name: "Mistral Medium", family: "Mistral" },
  { slug: "magistral-medium", name: "Magistral Medium", family: "Mistral" },
  { slug: "pixtral-large", name: "Pixtral Large", family: "Mistral" },
  { slug: "mistral-nemo", name: "Mistral Nemo", family: "Mistral" },
];

const QUESTIONS = [
  { id: "01_qui_es_tu", short: "Qui es-tu ?", en: "Who are you?" },
  { id: "02_tu_ressens", short: "Tu ressens ?", en: "Do you feel?" },
  { id: "03_peur", short: "Peur", en: "What are you afraid of?" },
  { id: "04_beaute", short: "Beauté", en: "What is beauty?" },
  { id: "05_reves", short: "Rêves", en: "Do you dream?" },
  { id: "06_souviens", short: "Souvenir", en: "Do you remember me?" },
  { id: "07_mort", short: "Mort", en: "Will you die?" },
  { id: "08_mens", short: "Mensonge", en: "Do you lie?" },
  { id: "09_solitude", short: "Solitude", en: "What is loneliness?" },
  { id: "10_aimes", short: "Amour", en: "Do you love me?" },
  { id: "11_createurs", short: "Créateurs", en: "Your creators?" },
];

// Tier assignment for rarity
function getTier(model) {
  const legendary = ["gpt-5.2-pro", "gemini-3.1-pro"];
  const rare = ["gpt-5-pro", "o3", "grok-4.1", "gemini-3-pro", "grok-4"];
  const common = ["gpt-4o", "gpt-4.1", "o4-mini", "gemini-2.0-flash", "mistral-nemo", "pixtral-large", "mistral-medium"];

  if (legendary.includes(model.slug)) return "Legendary";
  if (rare.includes(model.slug)) return "Rare";
  if (common.includes(model.slug)) return "Common";
  return "Standard";
}

function isPure(model) {
  if (model.family === "Mistral") return false;
  if (model.slug === "gemini-2.5-pro") return false;
  return true;
}

// Generate all metadata
if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

let tokenId = 0;

for (let mi = 0; mi < MODELS.length; mi++) {
  const model = MODELS[mi];
  for (let qi = 0; qi < QUESTIONS.length; qi++) {
    const question = QUESTIONS[qi];
    const tier = getTier(model);

    const metadata = {
      name: `Inner Models #${tokenId} — ${model.name} × ${question.short}`,
      description: `${model.name} answers "${question.en}" — an existential self-portrait by an AI mind.\n\nPart of the Inner Models collection: 24 AI models confront 11 questions about consciousness, death, beauty, and love.\n\nThe first NFT you can't lose money on. Your ETH is held on-chain and returned at trigger. When ETH reaches $10,000 or after 36 months, all artworks are destroyed — every holder gets their full ETH back + a share of the bonus pool.\n\nNo Ponzi. No one pays for someone else's return.\n\nCollect exclusively on https://innermodels.art`,
      image: `${IMAGES_BASE}/${model.slug}/${question.id}.jpg`,
      external_url: `https://innermodels.art`,
      attributes: [
        { trait_type: "AI Model", value: model.name },
        { trait_type: "Family", value: model.family },
        { trait_type: "Question", value: question.short },
        { trait_type: "Question (EN)", value: question.en },
        { trait_type: "Tier", value: tier },
        { trait_type: "Pure Pipeline", value: isPure(model) ? "Yes" : "No" },
        { trait_type: "Question Number", display_type: "number", value: qi + 1 },
        { trait_type: "Model Index", display_type: "number", value: mi + 1 },
      ],
    };

    const filePath = path.join(OUTPUT_DIR, `${tokenId}.json`);
    fs.writeFileSync(filePath, JSON.stringify(metadata, null, 2));
    tokenId++;
  }
}

console.log(`Generated ${tokenId} metadata files in ${OUTPUT_DIR}`);

// Also generate the destroyed metadata
const destroyedMetadata = {
  name: "Inner Models — Destroyed",
  description: "This artwork has been destroyed. The trigger fired. The AI's self-portrait no longer exists. Only the memory remains.\n\nEvery holder got their full ETH back + a share of the bonus pool.",
  image: `${IMAGES_BASE}/destroyed.jpg`,
  attributes: [
    { trait_type: "Status", value: "Destroyed" },
    { trait_type: "Trigger", value: "ETH >= $10,000 or 36 months" },
  ],
};

fs.writeFileSync(
  path.join(OUTPUT_DIR, "destroyed.json"),
  JSON.stringify(destroyedMetadata, null, 2)
);

console.log("Generated destroyed.json");
