"""Plugin pytest du bundle sandbox (chargé par scripts/sandbox/test.sh avec `-p sandbox.pytest_force_cpu`).

Le torch de PyPI est un build CUDA : sans GPU ni pilote, `comfy.model_management` plante à l'import tant que
`--cpu` n'est pas positionné. La CI amont utilise le torch CPU, où ce cas n'existe pas. Ce plugin reproduit ce
comportement en forçant le mode CPU avant la collecte, pour que chaque dossier de tests puisse se lancer seul.
"""
from comfy.cli_args import args

args.cpu = True
