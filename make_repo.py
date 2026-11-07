#!/usr/bin/env python3
"""Делает из .deb файлов простой репозиторий для Sileo / Cydia.

Использование:
    python3 make_repo.py ПАПКА_С_DEB ПАПКА_РЕПО

Пример:
    python3 make_repo.py packages docs
Все .deb из первой папки копируются в ПАПКА_РЕПО/debs, а рядом создаются
файлы Packages, Packages.gz, Packages.bz2, Release и index.html.
"""
import bz2
import glob
import gzip
import hashlib
import io
import os
import shutil
import sys
import tarfile


def read_ar(path):
    """Читает .deb (это архив формата ar) и возвращает {имя: байты}."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"!<arch>\n":
        raise ValueError("не похоже на .deb: " + path)
    pos = 8
    members = {}
    while pos + 60 <= len(data):
        header = data[pos:pos + 60]
        name = header[:16].decode().strip().rstrip("/")
        size = int(header[48:58].decode().strip())
        pos += 60
        members[name] = data[pos:pos + size]
        pos += size
        if pos % 2:
            pos += 1
    return members


def read_control(path):
    """Достаёт текст файла control из .deb."""
    members = read_ar(path)
    for name, blob in members.items():
        if name.startswith("control.tar"):
            with tarfile.open(fileobj=io.BytesIO(blob), mode="r:*") as tar:
                for member in tar.getmembers():
                    if member.name in ("control", "./control"):
                        return tar.extractfile(member).read().decode("utf-8").strip()
    raise ValueError("в .deb нет файла control: " + path)


def hashes(path):
    md5, sha1, sha256 = hashlib.md5(), hashlib.sha1(), hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            md5.update(chunk)
            sha1.update(chunk)
            sha256.update(chunk)
    return md5.hexdigest(), sha1.hexdigest(), sha256.hexdigest()


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    src_dir, repo_dir = sys.argv[1], sys.argv[2]
    debs_dir = os.path.join(repo_dir, "debs")
    os.makedirs(debs_dir, exist_ok=True)

    # 1. Копируем новые .deb в репозиторий
    for deb in glob.glob(os.path.join(src_dir, "*.deb")):
        shutil.copy2(deb, debs_dir)

    # 2. Собираем список пакетов из всех .deb в репозитории
    entries = []
    for deb in sorted(glob.glob(os.path.join(debs_dir, "*.deb"))):
        control = read_control(deb)
        md5, sha1, sha256 = hashes(deb)
        entries.append(
            control
            + "\nFilename: debs/" + os.path.basename(deb)
            + "\nSize: " + str(os.path.getsize(deb))
            + "\nMD5sum: " + md5
            + "\nSHA1: " + sha1
            + "\nSHA256: " + sha256
            + "\n"
        )
    packages = "\n".join(entries).encode("utf-8")

    # 3. Записываем Packages (обычный, gz и bz2)
    with open(os.path.join(repo_dir, "Packages"), "wb") as f:
        f.write(packages)
    with gzip.open(os.path.join(repo_dir, "Packages.gz"), "wb") as f:
        f.write(packages)
    with bz2.open(os.path.join(repo_dir, "Packages.bz2"), "wb") as f:
        f.write(packages)

    # 4. Release
    release = (
        "Origin: IconOpacity repo\n"
        "Label: IconOpacity repo\n"
        "Suite: stable\n"
        "Version: 1.0\n"
        "Codename: ios\n"
        "Architectures: iphoneos-arm\n"
        "Components: main\n"
        "Description: Personal tweak repository\n"
    )
    with open(os.path.join(repo_dir, "Release"), "w", encoding="utf-8") as f:
        f.write(release)

    # 5. Простая страница (если своей страницы ещё нет)
    index_path = os.path.join(repo_dir, "index.html")
    if not os.path.exists(index_path):
        with open(index_path, "w", encoding="utf-8") as f:
            f.write("<!doctype html><meta charset='utf-8'><title>IconOpacity repo</title>"
                    "<h1>IconOpacity repo</h1><p>Добавь эту ссылку в Sileo как репозиторий.</p>")

    print("Готово: пакетов в репозитории:", len(entries))


if __name__ == "__main__":
    main()
