from flask import Flask, request, jsonify
from sentence_transformers import SentenceTransformer, util
from PIL import Image
import requests
from io import BytesIO

app = Flask(__name__)

# Load CLIP model (for images)
model = SentenceTransformer("clip-ViT-B-32")

@app.route("/image_similarity", methods=["POST"])
def image_similarity():
    try:
        data = request.json
        img_url1 = data["img1"]
        img_url2 = data["img2"]

        # Download images
        img1 = Image.open(BytesIO(requests.get(img_url1).content)).convert("RGB")
        img2 = Image.open(BytesIO(requests.get(img_url2).content)).convert("RGB")

        # Encode into embeddings
        emb1 = model.encode(img1, convert_to_tensor=True)
        emb2 = model.encode(img2, convert_to_tensor=True)

        # Cosine similarity
        score = util.cos_sim(emb1, emb2).item()

        return jsonify({
            "similarity": round(score, 3),
            "match": score >= 0.85   # adjust threshold
        })
    except Exception as e:
        return jsonify({"error": str(e)})

if __name__ == "__main__":
    app.run(port=5001)  

