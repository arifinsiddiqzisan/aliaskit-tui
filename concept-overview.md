###Command Parameter System
##Concept Overview
There are two types of parameters:

Pre Parameters
Post Parameters
Pre Parameters use { } and Post Parameters use [ ].

##Definitions
Pre Parameters are fixed during command creation. They represent constant or mapped values.

Post Parameters are dynamic and provided during execution.


// Example base command
ffmpeg -i input.mp4 -vn -c:a libmp3lame output_audio.mp3
Command Transformation

// Genuine Command
ffmpeg -i [input] -vn -c:a {type} [output]

// Post Parameters
["input", "output"]

// Pre Parameters Mapping
{
  "type": {
    "mp3": "libmp3lame",
    "wav": "pcm_s16le",
    "aac": "aac",
    "flac": "flac"
  }
}
Custom Command

extract-audio [input.mp4] [output] {type}
Two Post Parameters: input, output
One Pre Parameter: type
Post = dynamic
Pre = mapped & fixed
Behavior
{type} controls encoding format
[input.mp4] enforces file type
[output] extension depends on type
Usage

extract-audio input="home/download/video.mp4" 
              output="home/download/audio.mp3" 
              type="mp3"
Execution Flow

[input]  → "home/download/video.mp4"
{type}   → "libmp3lame"
[output] → "audio.mp3"
Final Command

ffmpeg -i home/download/video.mp4 -vn -c:a libmp3lame audio.mp3