import os
from subprocess import call

import matplotlib.pyplot as plt

BASE_PATH = os.path.join(os.getcwd(), 'images')


def st_time(func):
    from functools import wraps
    import time

    @wraps(func)
    def st_func(*args, **keyArgs):
        t1 = time.time()
        func(*args, **keyArgs)
        t2 = time.time()
        return t2 - t1

    return st_func


@st_time
def cpython(image_path):
    from pyTGA.measure import main
    return main(image_path)


@st_time
def pypy(image_path):
    return call(["pypy", "pyTGA/measure.py", image_path])


@st_time
def nuitka(image_path):
    return call(["pyTGA/measure.exe", image_path])


@st_time
def numba(image_path):
    pass


@st_time
def nim(image_path):
    return call(["./nimtga", image_path])


@st_time
def pymod_nim(image_path):
    import pymodtga
    return pymodtga.main(image_path)


fig = plt.figure()
ax = fig.add_subplot(111)
x = [0, 15, 150, 512, 1024, 2048, 4096]
tests = [cpython, pypy, nuitka, nim, pymod_nim]
# tests = [nim, ]

for t in tests:
    res = [0, ]
    for image in ["pie_15_11.tga", "pie_150_113.tga",
                  "pie_512_384.tga", "pie_1024_768.tga",
                  "pie_2048_1536.tga", "pie_4096_3072.tga"]:
        image_path = os.path.join(BASE_PATH, image)
        res.append(t(image_path))
    ax.plot(x, res, label=t.__name__)

plt.title('speed comparison')

legend = ax.legend(loc='upper left', shadow=True)
legend.get_frame().set_facecolor('#00FFCC')

ax.set_xticks(x)
ax.set_ylabel("seconds")
ax.set_xlabel("image size")
labels = ax.set_xticklabels(x)
ax.grid(True)


# plt.show()
plt.savefig("benchmark.png", bbox_inches='tight')
