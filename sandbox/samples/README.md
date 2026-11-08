# Données d'exemple locales

`workflows/*.json` : graphes au format API de ComfyUI qui n'utilisent **aucun modèle** (pas de poids dans le sandbox,
pas de GPU). Ils servent au smoke test (`make smoke`) et de modèles pour écrire d'autres graphes.
`input/example.png` (déjà dans le dépôt) est l'image d'entrée de `02_image_pipeline.json`.

Lancer un graphe précis sur un serveur local éphémère :
    python scripts/sandbox/smoke.py --workflow sandbox/samples/workflows/02_image_pipeline.json
