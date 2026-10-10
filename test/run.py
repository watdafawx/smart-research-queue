"""Headless check of Smart Research Queue: vanilla + Space Age + flib (from your mods folder): python test/run.py"""
from factorio_paths import main

main(__file__, {"srq-test": 400}, user_mods=["flib"])
