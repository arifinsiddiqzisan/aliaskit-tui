#!/usr/bin/env bash
# CATEGORY: complex
# MODULE: ffmpeg
## extract-audio
# @desc  complex
# @usage extract-audio
# @example extract-audio
ffmpeg_extract_audio() {
    __ak_complex_exec "/home/zisan/Downloads/aliaskit-tui/custom/modules/complex/ffmpeg/extract-audio/parameters.json" "$@"
}
alias extract-audio='ffmpeg_extract_audio'
