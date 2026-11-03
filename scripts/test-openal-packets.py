#!/usr/bin/env python3
"""Check the real OpenAL writer without an audio device or full frontend build."""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parent.parent
source = Path(os.environ.get('OPENAL_SOURCE', repo / 'compile/RetroArch/audio/drivers/openal.c')).read_text()
state = source[source.index('typedef struct al\n'):source.index('static void al_free')]
writer = source[source.index('static ssize_t al_write('):source.index('static bool al_stop')]
avail = source[source.index('static size_t al_write_avail('):source.index('static size_t al_buffer_size')]
harness = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#define OPENAL_BUFSIZE 1024
#define MIN(a,b) ((a)<(b)?(a):(b))
#define AL_SOURCE_STATE 1
#define AL_PLAYING 1
typedef unsigned ALuint;
typedef int ALint;
typedef int ALsizei;
typedef int ALenum;
typedef void ALCdevice;
typedef void ALCcontext;
static uint8_t recorded[100000];
static size_t recorded_size;
static unsigned packets;
'''
stubs = r'''
static bool al_get_buffer(al_t *al, ALuint *buffer)
{
    if (!al->res_ptr) { assert(al->nonblock); return false; }
    *buffer = (ALuint)al->res_ptr--;
    return true;
}
static bool al_unqueue_buffers(al_t *al) { return false; }
static void alBufferData(ALuint id, ALenum format, const void *data, ALsizei size, int rate)
{
    assert(size == OPENAL_BUFSIZE);
    assert(recorded_size + size <= sizeof recorded);
    memcpy(recorded + recorded_size, data, size);
    recorded_size += size;
    ++packets;
}
static void alSourceQueueBuffers(ALuint source, ALsizei count, const ALuint *buffers) {}
static void alGetSourcei(ALuint source, ALenum property, ALint *value) { *value = AL_PLAYING; }
static void alSourcePlay(ALuint source) {}
'''
tests = r'''
static void reset(al_t *al, size_t buffers)
{
    memset(al, 0, sizeof *al);
    al->res_ptr = al->num_buffers = buffers;
    al->rate = 48000;
    recorded_size = packets = 0;
}
int main(void)
{
    uint8_t input[32768 + 300];
    al_t al;
    size_t i, pos;
    for (i = 0; i < sizeof input; ++i) input[i] = (uint8_t)(i * 79U);
    reset(&al, 64);
    assert(al_write(&al, input, sizeof input) == sizeof input);
    assert(recorded_size == 32768 && al.partial_size == 300);
    assert(!memcmp(recorded, input, recorded_size));
    assert(!memcmp(al.partial_data, input + recorded_size, 300));
    assert(al_write_avail(&al) == 64 * OPENAL_BUFSIZE - sizeof input);
    reset(&al, 64);
    // Stereo 16-bit frames, with writes shorter/longer than a device packet.
    for (pos = 0, i = 0; pos < sizeof input; ++i) {
        const size_t writes[] = {4, 2940, 16, 3200, 996, 2048, 128};
        size_t size = MIN(sizeof input - pos, writes[i % 7]);
        assert(al_write(&al, input + pos, size) == (ssize_t)size);
        pos += size;
    }
    assert(recorded_size == 32768 && al.partial_size == 300);
    assert(!memcmp(recorded, input, recorded_size));
    assert(!memcmp(al.partial_data, input + recorded_size, 300));
    assert(al_write_avail(&al) == 64 * OPENAL_BUFSIZE - sizeof input);
    reset(&al, 2);
    al.nonblock = true;
    assert(al_write(&al, input, 200) == 200);
    assert(al.res_ptr == 1 && al_write_avail(&al) == 1848);
    assert(al_write(&al, input + 200, 2000) == 1848);
    assert(recorded_size == 2048 && al_write_avail(&al) == 0);
    assert(!memcmp(recorded, input, recorded_size));
    assert(al_write(&al, input + 2048, 100) == 0);
    al.res_ptr = 1; // Consumer releases a device buffer.
    assert(al_write(&al, input + 2048, 100) == 100);
    assert(al_write_avail(&al) == 924);
    assert(al_write(&al, input + 2148, 1000) == 924);
    assert(recorded_size == 3072 && !memcmp(recorded, input, recorded_size));
    puts("OpenAL: byte-exact packet assembly, partial writes, reservation and backpressure passed");
    return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='openal-packets-') as temp:
    path = Path(temp)
    (path / 'test.c').write_text(harness + state + stubs + writer + avail + tests)
    subprocess.run([os.environ.get('CC', 'cc'), '-std=c99', '-O2', '-Wall', '-Wextra',
                    '-Werror', '-Wno-unused-parameter', str(path / 'test.c'), '-o', str(path / 'test')], check=True)
    subprocess.run([str(path / 'test')], check=True)
