# LT Wallpaper Gallery — runtime image with pre-baked ltheory tree.
#
# Build on a machine with ≥4 GiB RAM (compiling LibPHX on 1 GiB will thrash/fail).
# Deploy the image to smaller hosts; use LT_GALLERY_PROFILE=small at runtime.
#
#   docker build -t lt-wallpaper-gallery -f Dockerfile ..
#   docker run --rm -p 8787:8787 -v gallery-data:/var/lib/lt-wallpaper/gallery \
#     -e LT_GALLERY_PROFILE=small lt-wallpaper-gallery

FROM ubuntu:24.04 AS build

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git git-lfs \
    python3 g++ \
    libglew-dev libsdl2-dev libfreetype-dev libluajit-5.1-dev \
    libgl1-mesa-dev \
    lua-filesystem \
    ca-certificates curl \
    && git lfs install \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
# Build context = lt-wallpaper/ (parent of gallery/)
COPY . /src/

ENV LTHEORY_DIR=/opt/lt-wallpaper/ltheory
RUN mkdir -p /opt/lt-wallpaper \
    && ./setup.sh \
    && cp -a overlay/script/App/Wallpaper.lua "$LTHEORY_DIR/script/App/Wallpaper.lua"

FROM ubuntu:24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    libglew2.2 libsdl2-2.0-0 libfreetype6 libluajit-5.1-2 \
    libgl1 libgl1-mesa-dri \
    xvfb xauth \
    lua-filesystem \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/lt-wallpaper/ltheory /opt/lt-wallpaper/ltheory
COPY gallery /opt/lt-wallpaper/gallery

ENV LTHEORY_ROOT=/opt/lt-wallpaper/ltheory \
    LT_GALLERY_HOST=0.0.0.0 \
    LT_GALLERY_PORT=8787 \
    LT_GALLERY_DATA=/var/lib/lt-wallpaper/gallery \
    LT_GALLERY_PROFILE=small \
    LT_GALLERY_RATE_SEC=60 \
    LT_GALLERY_BAKE_TIMEOUT=600

RUN mkdir -p /var/lib/lt-wallpaper/gallery/images \
    && useradd --system --home /opt/lt-wallpaper --shell /usr/sbin/nologin ltwallpaper \
    && chown -R ltwallpaper:ltwallpaper /opt/lt-wallpaper /var/lib/lt-wallpaper

USER ltwallpaper
WORKDIR /opt/lt-wallpaper/gallery
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8787/api/health')"

CMD ["python3", "server.py"]
