from flask import Flask, request, jsonify
from sentence_transformers import SentenceTransformer, util

app = Flask(__name__)

# Load NLP model once (downloads on first run)
model = SentenceTransformer("all-MiniLM-L6-v2")

@app.route("/similarity", methods=["POST"])
def similarity():
    data = request.json
    desc1 = data["desc1"]
    desc2 = data["desc2"]

    emb1 = model.encode(desc1, convert_to_tensor=True)
    emb2 = model.encode(desc2, convert_to_tensor=True)
    score = util.cos_sim(emb1, emb2).item()  # cosine similarity score

    return jsonify({"similarity": score})

if __name__ == "__main__":
    app.run(port=5000)
