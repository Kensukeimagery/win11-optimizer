"""Builds docs/Manual_EN_<version>.pdf and docs/Manual_TH_<version>.pdf from docs/src/manual_en.html and manual_th.html.

Needs: Microsoft Edge (headless print) and PyMuPDF (pip install pymupdf).  Run from anywhere:  python docs/src/build_manuals.py
The contents page lists page numbers. They are found in the first print (the pages where each section title appears as a large heading),
written into the HTML, and the file is printed again, so the numbers in the source always match the PDF.
"""
import io
import os
import re
import subprocess
import shutil
import tempfile
import sys

import pymupdf

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
EDGE = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
if not os.path.exists(EDGE):
    EDGE = r'C:\Program Files\Microsoft\Edge\Application\msedge.exe'
VERSION = io.open(os.path.join(REPO, 'VERSION'), encoding='utf-8').read().strip()
TAG = 'v' + VERSION


def print_pdf(html_path, pdf_path):
    if os.path.exists(pdf_path):
        os.remove(pdf_path)
    url = 'file:///' + html_path.replace('\\', '/')
    # an own profile folder: with Edge (or a WebView2 program) already running, a headless start without one hands the job
    # to that running instance and exits without writing the PDF
    profile = tempfile.mkdtemp(prefix='edge_pdf_')
    try:
        subprocess.run([EDGE, '--headless', '--disable-gpu', '--no-pdf-header-footer', '--generate-pdf-document-outline',
                        '--user-data-dir=' + profile, '--print-to-pdf=' + pdf_path, url], check=True, timeout=180)
    finally:
        shutil.rmtree(profile, ignore_errors=True)
    if not os.path.exists(pdf_path):
        raise RuntimeError('Edge did not write ' + pdf_path)


def section_pages(pdf_path, titles):
    """titles: {section id: heading text}. Returns {section id: 1-based page} using large heading text (about 21 pt)."""
    doc = pymupdf.open(pdf_path)
    found = {}
    for pno in range(1, doc.page_count):             # the cover (page 1) holds the contents list, not the headings
        for block in doc[pno].get_text('dict')['blocks']:
            for line in block.get('lines', []):
                big = [s['text'] for s in line['spans'] if s['size'] >= 19]
                text = ''.join(big).strip()         # a title can be split into several spans (mixed Thai and Latin text)
                if text:
                    for sec, title in titles.items():
                        if sec not in found and text == title:
                            found[sec] = pno + 1
    return found, doc.page_count


def build(lang, kind='manual'):
    src = os.path.join(HERE, f'{kind}_{lang}.html')
    out = os.path.join(REPO, 'docs', (f'Manual_{lang.upper()}_{TAG}.pdf' if kind == 'manual' else f'GPU_Driver_Guide_{lang.upper()}.pdf'))
    text = io.open(src, encoding='utf-8').read()
    titles = {}
    for m in re.finditer(r'<li><a href="#(sec-[a-z]+)">(.*?)</a>', text):
        titles[m.group(1)] = re.sub(r'<[^>]+>', '', m.group(2)).strip()
    # the banner headings are shorter than the contents entries: take them from the section banners
    for m in re.finditer(r'<div class="banner" id="(sec-[a-z]+)"><h1>(.*?)</h1>', text):
        titles[m.group(1)] = re.sub(r'<[^>]+>', '', m.group(2)).strip()
    tmp = os.path.join(os.environ.get('TEMP', HERE), f'{kind}_{lang}_pass.pdf')
    for attempt in range(3):
        print_pdf(src, tmp)
        pages, total = section_pages(tmp, titles)
        missing = [s for s in titles if s not in pages]
        if missing:
            raise SystemExit(f'{lang}: headings not found in the PDF: {missing}')
        new = text
        for sec, pg in pages.items():
            new = re.sub(r'(<span class="pg" data-sec="%s">)\d+(</span>)' % sec, r'\g<1>%d\g<2>' % pg, new)
        if new == text:
            break
        text = new
        io.open(src, 'w', encoding='utf-8', newline='\n').write(text)
    print_pdf(src, out)
    print(f'{kind} {lang}: {total} pages ->', out, {k: v for k, v in sorted(pages.items(), key=lambda kv: kv[1])})


if __name__ == '__main__':
    args = sys.argv[1:]
    kinds = [k for k in ('manual', 'gpu_guide') if k in args] or ['manual', 'gpu_guide']   # no name: build both
    langs = [a for a in args if a in ('en', 'th')] or ['en', 'th']
    for kind in kinds:
        for lang in langs:
            build(lang, kind)
