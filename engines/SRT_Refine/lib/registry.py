# -*- coding: utf-8 -*-
"""Resolve language plugin."""

from __future__ import annotations

from plugins.base import RefinePlugin
from plugins.en import EnglishPlugin
from plugins.generic import GenericPlugin
from plugins.ja_mecab import JapaneseMecabPlugin
from plugins.vi import VietnamesePlugin
from plugins.zh import ChinesePlugin

_PLUGINS: list[RefinePlugin] = [
    JapaneseMecabPlugin(),
    EnglishPlugin(),
    VietnamesePlugin(),
    ChinesePlugin(),
    GenericPlugin(),
]

_GENERIC = GenericPlugin()


def get_plugin(lang: str) -> RefinePlugin:
    lang = (lang or "auto").lower().split("-")[0]
    for plugin in _PLUGINS:
        if plugin.supports(lang):
            return plugin
    return _GENERIC
