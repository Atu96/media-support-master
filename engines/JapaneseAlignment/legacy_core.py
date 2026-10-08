#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import difflib
import os
import re
import subprocess
import sys
import unicodedata
import MeCab


def _mecab_dic_dir():
    env = os.environ.get("MECAB_DICDIR")
    if env and os.path.isdir(env):
        return env
    for candidate in (
        "/opt/homebrew/lib/mecab/dic/ipadic",
        "/usr/local/lib/mecab/dic/ipadic",
    ):
        if os.path.isdir(candidate):
            return candidate
    try:
        prefix = subprocess.check_output(
            ["brew", "--prefix", "mecab-ipadic"], text=True, stderr=subprocess.DEVNULL
        ).strip()
        path = f"{prefix}/lib/mecab/dic/ipadic"
        if os.path.isdir(path):
            return path
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return "/opt/homebrew/lib/mecab/dic/ipadic"


_MECAB_TAGGER = None


def _get_mecab_tagger():
    global _MECAB_TAGGER
    if _MECAB_TAGGER is None:
        dic = _mecab_dic_dir()
        _MECAB_TAGGER = MeCab.Tagger(f"-r /dev/null -d {dic}")
    return _MECAB_TAGGER

# === CẤU HÌNH YOUTUBE TIN TỨC CHUYÊN NGHIỆP ===
MAX_CPS = 14.0
MIN_DURATION = 0.8
MAX_DURATION = 6.5
MIN_GAP = 0.05
END_PAD = 0.15
MAX_LINE_CHARS      = 18  # YouTube News: tối đa 18 ký tự/dòng (chuẩn NHK/Netflix JP)
MAX_BLOCK_CHARS     = MAX_LINE_CHARS * 2  # 36: ngưỡng ép split theo ký tự (2 dòng × 18)
WRAP_PUNCT_PRIORITY = 4   # Ưu tiên ngắt sau dấu câu (、！？…――): cho phép lệch tối đa N ký tự so với điểm cân đối

# Bộ từ cấm đứng đầu dòng (Kinsoku Head)
KINSOKU_HEAD_PROHIBITED = {
    "が", "は", "を", "に", "へ", "と", "より", "から", "で", "や", "の", "も", "か",
    "、", "。", "・", "！", "？", "――", "」", "』", "）", "％", "%", "减", "減", "だ", "です"
}

# Bộ từ cấm đứng cuối dòng (Kinsoku Tail)
KINSOKU_TAIL_PROHIBITED = {"「", "『", "（"}

# Chuỗi nguyên tử cấm bẻ gãy tại ranh giới Timecode
ATOMIC_COMPOUNDS = [
    "肉そぼろ",
    "五分の一",
    "あなた自身",
]

# Đơn vị đếm cấm ngắt Timecode khi đứng ngay sau số
COUNTER_UNITS = {
    "元", "人", "円", "兆", "億", "万",
    "兆円", "億円", "万円", "万人",
    "匹", "頭", "羽", "冊", "本", "枚", "台", "個", "基", "機",
    "杯", "膳", "倍", "回", "度", "時間",
    "年", "月", "日", "歳", "票", "点", "棟", "件",
    "粒", "銭", "品", "割",
}


def parse_srt_time(time_str):
    parts = re.split(r"[:,.]", time_str.strip())
    h, m, s, ms = map(int, parts)
    return h * 3600 + m * 60 + s + ms / 1000.0


def format_srt_time(seconds):
    total_s = int(seconds)
    ms = int(round((seconds - total_s) * 1000))
    if ms >= 1000:
        total_s += 1
        ms -= 1000
    h = total_s // 3600
    m = (total_s % 3600) // 60
    s = total_s % 60
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def read_whisper_srt(filename):
    with open(filename, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    blocks = re.split(r"\n\s*\n", content.strip())
    srt_data = []
    for block in blocks:
        lines = [l.strip() for l in block.split("\n") if l.strip()]
        if len(lines) >= 3:
            t_parts = lines[1].split("-->")
            if len(t_parts) == 2:
                srt_data.append({
                    "start": parse_srt_time(t_parts[0]),
                    "end": parse_srt_time(t_parts[1]),
                    "text": "".join(lines[2:]),
                })
    return srt_data


def clean_and_split_script(script_path):
    with open(script_path, "r", encoding="utf-8") as f:
        content = f.read()
    content = unicodedata.normalize("NFKC", content)
    # Xóa marker dạng 【...】
    content = re.sub(r"【[^】]*】\s*", "", content)
    # Xóa section marker dạng "— 見出し " hoặc "— 見出し:サブ " (production notes)
    content = re.sub(r"—\s+\S+\s+", "", content)
    # Xóa markdown bold dạng **text** hoặc **text
    content = re.sub(r"\*{1,2}", "", content)
    content = re.sub(r"\s+", " ", content).strip()
    raw_sentences = re.split(r"(?<=[。！？])\s*", content)
    return [s.strip() for s in raw_sentences if s.strip()]


def tokenize_mecab(text):
    tagger = _get_mecab_tagger()
    node = tagger.parseToNode(text)
    tokens = []
    while node:
        surf = node.surface
        if surf:
            feat = node.feature.split(",")
            tokens.append({
                "surface": surf,
                "pos": feat[0] if len(feat) > 0 else "",
                "pos_detail": feat[1] if len(feat) > 1 else "",
                "pos_detail2": feat[2] if len(feat) > 2 else "",
                "conj_form": feat[5] if len(feat) > 5 else "",  # 活用形: 連体形 / 連用形 / etc.
            })
        node = node.next
    return tokens


def normalize_for_matching(text):
    return re.sub(r"[。、！？「」『』（）\s\n\-―]", "", text)


def is_split_safe_boundary(prev_tok, next_tok):
    """BỘ KIỂM DUYỆT AST: Khóa chết ranh giới Timecode"""
    if next_tok is None:
        return True
    next_surf = next_tok["surface"]
    prev_surf = prev_tok["surface"] if prev_tok else ""

    # 1. Cấm rớt Trợ từ, Dấu câu, Đơn vị xuống đầu Timecode mới
    if next_surf in KINSOKU_HEAD_PROHIBITED or next_tok["pos"] == "助詞":
        return False

    # 2. Cấm vứt ngoặc mở bơ vơ ở Timecode cũ
    if prev_surf in KINSOKU_TAIL_PROHIBITED:
        return False

    # 3. Bảo vệ cụm động từ phụ trợ
    if next_tok["pos"] in {"助動詞", "接尾"}:
        return False
    if next_tok["pos"] == "動詞" and next_surf in {
        "する", "した", "している", "て", "た", "ている", "たい", "られる", "られ", "ない", "ず", "せる", "させる"
    }:
        return False
    if prev_surf in {"て", "で", "に", "を"} and next_tok["pos"] == "動詞":
        return False

    # 4. Khóa Đơn vị đếm (Counter Lock)
    # FIX: check pos_detail (không phải pos) để nhận diện token số (名詞,数,...)
    prev_is_number = prev_tok and prev_tok.get("pos_detail", "") == "数"
    next_is_counter = (
        next_surf in COUNTER_UNITS or
        next_tok.get("pos_detail2", "") == "助数詞"
    )
    if prev_is_number and next_is_counter:
        return False
    # Bảo vệ tổng quát: số + danh từ ngắn (<= 2 ký tự)
    if prev_is_number and next_tok["pos"] == "名詞" and len(next_surf) <= 2:
        return False

    # 5. Khóa Trợ động từ khép câu (Closing Auxiliary Lock)
    # だ/です đã trong KINSOKU_HEAD_PROHIBITED, た đã bắt qua 助動詞
    # Thêm explicit check cho った + ている (đề phòng MeCab parse edge case)
    if next_surf in {"った", "ている"}:
        return False

    # 6. Khóa: 日本の(Sở hữu) + 人口(Danh)
    if prev_surf == "の" and next_tok["pos"] in {"名詞", "代名詞"}:
        return False

    # 7. Bảo vệ mệnh đề định ngữ: 動詞(連体形) + 名詞
    # Vd: 眠る/場所, ためらう/若者, 働く/人, 暮らす/人々
    if (prev_tok and prev_tok["pos"] == "動詞"
            and prev_tok.get("conj_form", "") == "連体形"
            and next_tok["pos"] in {"名詞", "代名詞"}):
        return False

    return True


def split_breaks_atomic(stream, split_idx):
    """Trả về True nếu cắt stream tại split_idx sẽ xé lẻ một cụm nguyên tử."""
    left_text = "".join(t[0]["surface"] for t in stream[:split_idx])
    right_text = "".join(t[0]["surface"] for t in stream[split_idx:])
    full_text = left_text + right_text
    split_point = len(left_text)
    for compound in ATOMIC_COMPOUNDS:
        pos = full_text.find(compound)
        while pos != -1:
            if pos < split_point < pos + len(compound):
                return True
            pos = full_text.find(compound, pos + 1)
    return False


def split_sentence_by_physical_times(sent, char_times, char_end_times=None, max_dur=6.5):
    """Chẻ câu dài theo mốc thời gian vật lý thực tế của từng cặp token.

    char_times      — list thời điểm BẮT ĐẦU của mỗi ký tự (từ Whisper block start)
    char_end_times  — list thời điểm KẾT THÚC của mỗi ký tự (từ Whisper block end).
                      Nếu có, dùng để tính end_t chính xác thay vì start+END_PAD.
    """
    if not char_times or len(sent) != len(char_times):
        return [(sent, 0.0, 2.0)]

    has_end = char_end_times and len(char_end_times) == len(char_times)

    start_t = char_times[0]
    end_t = (char_end_times[-1] if has_end else char_times[-1]) + END_PAD

    if (end_t - start_t) <= max_dur and len(sent) <= MAX_BLOCK_CHARS:
        return [(sent, start_t, end_t)]

    tokens = tokenize_mecab(sent)
    stream = []
    c_idx = 0
    for tok in tokens:
        t_len = len(tok["surface"])
        tok_starts = char_times[c_idx : c_idx + t_len]
        tok_ends   = char_end_times[c_idx : c_idx + t_len] if has_end else None
        stream.append((tok, tok_starts, tok_ends))
        c_idx += t_len

    def chunk_end(part):
        """End-time của phần cuối stream: dùng tok_ends[-1] nếu có."""
        last = part[-1]
        return (last[2][-1] if last[2] else last[1][-1]) + END_PAD

    def chunk_end_left(part):
        """End-time cho nửa trái khi bẻ đôi (thêm gap nhỏ hơn END_PAD)."""
        last = part[-1]
        return (last[2][-1] if last[2] else last[1][-1]) + 0.08

    chunks = []
    while stream:
        # Kiểm tra toàn bộ stream còn lại có vừa 1 Timecode không
        # (cả duration ≤ max_dur VÀ char count ≤ MAX_BLOCK_CHARS)
        stream_end      = (stream[-1][2][-1] if stream[-1][2] else stream[-1][1][-1])
        stream_text_len = sum(len(t[0]["surface"]) for t in stream)
        if stream_end - stream[0][1][0] <= max_dur and stream_text_len <= MAX_BLOCK_CHARS:
            text = "".join(t[0]["surface"] for t in stream)
            chunks.append((text, stream[0][1][0], chunk_end(stream)))
            break

        # Dò ngược tìm ranh giới an toàn
        safe_k = -1
        for k in range(len(stream) - 1, 0, -1):
            dur_left = stream[k - 1][1][-1] - stream[0][1][0]
            if dur_left > max_dur:
                continue
            next_tok_k = stream[k][0]
            next_next_tok_k = stream[k + 1][0] if k + 1 < len(stream) else None
            # Lookahead: cấm ngắt nếu next là số và next+1 là đơn vị đếm
            # Bảo vệ cụm [名詞]→[数]→[助数詞]: Vd ニンジン / 一本
            if (next_tok_k.get("pos_detail", "") == "数" and next_next_tok_k and
                    (next_next_tok_k["surface"] in COUNTER_UNITS or
                     next_next_tok_k.get("pos_detail2", "") == "助数詞")):
                continue
            if (is_split_safe_boundary(stream[k - 1][0], next_tok_k)
                    and not split_breaks_atomic(stream, k)):
                safe_k = k
                break

        if safe_k == -1:
            safe_k = max(1, len(stream) // 2)

        left_part = stream[:safe_k]
        text_left = "".join(t[0]["surface"] for t in left_part)
        chunks.append((text_left, left_part[0][1][0], chunk_end_left(left_part)))
        stream = stream[safe_k:]

    return chunks


def merge_tail_fragments(blocks):
    """Nâng dải đón rác lên <= 5 ký tự để bắt gọn 'ている。', 'ました。'"""
    if not blocks:
        return blocks
    merged = [blocks[0]]
    for text, start, end in blocks[1:]:
        dur = end - start
        prev_text, prev_start, prev_end = merged[-1]
        if dur <= 0.25 or len(text.strip()) <= 5:
            merged[-1] = (prev_text + text, prev_start, end)
        else:
            merged.append((text, start, end))
    return merged


def redistribute_cps_clusters(blocks, cps_threshold=None, cluster_gap=2.0):
    """Tái phân bổ timing cho cluster blocks CPS không khả thi.

    Khi Whisper bị drift ở B-roll/silence, nó dồn nhiều câu vào khoảng thời gian
    rất ngắn → CPS 30-76. Hàm này phát hiện cluster như vậy và phân bổ lại
    thời gian theo tỷ lệ độ dài ký tự.
    """
    if cps_threshold is None:
        cps_threshold = MAX_CPS * 2.0  # 28 CPS

    if not blocks:
        return blocks

    def block_cps(text, start, end):
        dur = end - start
        if dur <= 0:
            return float('inf')
        return len(text.replace('\n', '')) / dur

    impossible = [block_cps(t, s, e) > cps_threshold for t, s, e in blocks]
    result = list(blocks)
    i = 0
    while i < len(blocks):
        if not impossible[i]:
            i += 1
            continue
        # Mở rộng cluster
        j = i
        while (j + 1 < len(blocks) and impossible[j + 1]
               and blocks[j + 1][1] - blocks[j][2] <= cluster_gap):
            j += 1

        if j == i:
            # Cluster 1 block — giãn end theo MAX_CPS (overlap sửa ở main loop)
            text, s, e = blocks[i]
            char_count = len(text.replace('\n', ''))
            min_needed = max(char_count / MAX_CPS, MIN_DURATION)
            if e - s < min_needed:
                result[i] = (text, s, s + min_needed)
            i += 1
            continue

        # Cluster i→j — tái phân bổ theo tỷ lệ ký tự
        cluster = blocks[i:j + 1]
        cluster_start    = cluster[0][1]
        cluster_end      = cluster[-1][2]
        total_duration   = cluster_end - cluster_start
        total_chars      = sum(max(1, len(t.replace('\n', ''))) for t, s, e in cluster)

        if total_chars == 0 or total_duration <= 0:
            i = j + 1
            continue

        # B-roll drift: Whisper dồn quá nhiều chữ vào cửa sổ quá ngắn → giãn timeline
        min_needed_total = total_chars / MAX_CPS
        if total_duration < min_needed_total:
            next_cap = blocks[j + 1][1] if j + 1 < len(blocks) else cluster_start + min_needed_total + 5.0
            cluster_end = min(cluster_start + min_needed_total, next_cap - MIN_GAP)
            total_duration = max(cluster_end - cluster_start, MIN_DURATION)

        char_counts = [max(1, len(t.replace('\n', ''))) for t, s, e in cluster]
        ratios       = [c / total_chars for c in char_counts]
        durations    = [max(r * total_duration, MIN_DURATION) for r in ratios]

        total_alloc = sum(durations)
        if total_alloc > total_duration:
            scale = total_duration / total_alloc
            durations = [d * scale for d in durations]

        cur_time = cluster_start
        for k, (text, s, e) in enumerate(cluster):
            new_s = cur_time
            new_e = cur_time + durations[k]
            result[i + k] = (text, new_s, max(new_e, new_s + MIN_DURATION))
            cur_time = new_e + MIN_GAP

        i = j + 1

    return result


def finalize_block_timings(blocks):
    """MIN_GAP + MAX_CPS — chạy sau redistribute, sửa overlap do giãn timeline."""
    if not blocks:
        return blocks
    fixed = []
    for text, start, end in blocks:
        chars = len(text.replace("\n", ""))
        need = max(chars / MAX_CPS, MIN_DURATION) if chars else MIN_DURATION
        if fixed and start < fixed[-1][2] + MIN_GAP:
            start = fixed[-1][2] + MIN_GAP
        end = max(end, start + need)
        fixed.append((text, start, end))
    return fixed


def wrap_text_mecab(text, max_chars=MAX_LINE_CHARS):
    """Ngắt text thành ≤ 2 dòng tại ranh giới ngữ pháp tự nhiên.

    Ưu tiên theo thứ tự:
      1. Cả 2 dòng ≤ max_chars (18)
      2. Tôn trọng Kinsoku + AST boundary (is_split_safe_boundary)
      3. Bảo vệ ATOMIC_COMPOUNDS không bị xé giữa 2 dòng
      4. Cân đối chiều dài — chọn điểm ngắt gần giữa văn bản nhất

    Dùng cho DaVinci Resolve: SRT hiển thị \\n nguyên văn.
    """
    text = text.replace("\n", "")   # strip wrap cũ nếu re-process

    if len(text) <= max_chars:
        return text                 # 1 dòng, không cần wrap

    tokens = tokenize_mecab(text)
    if not tokens:
        # Fallback không có MeCab: cắt cứng tại max_chars
        return text[:max_chars] + "\n" + text[max_chars:]

    total_len = len(text)
    ideal     = total_len / 2.0    # mục tiêu: 2 dòng đều nhau

    # Tính offset ký tự bắt đầu của mỗi token
    tok_starts = []
    pos = 0
    for tok in tokens:
        tok_starts.append(pos)
        pos += len(tok["surface"])

    def is_atomic_broken(sp):
        """True nếu điểm cắt sp xé lẻ một ATOMIC_COMPOUND."""
        for compound in ATOMIC_COMPOUNDS:
            cp = text.find(compound)
            while cp != -1:
                if cp < sp < cp + len(compound):
                    return True
                cp = text.find(compound, cp + 1)
        return False

    # Dấu câu được ưu tiên ngắt sau (giảm score theo WRAP_PUNCT_PRIORITY)
    WRAP_PUNCT = {"、", "！", "？", "…", "――"}

    def find_best(char_limit):
        """Tìm điểm ngắt tốt nhất trong ngưỡng char_limit.

        Score = khoảng cách tới điểm giữa lý tưởng.
        Nếu token liền trước là dấu câu → trừ WRAP_PUNCT_PRIORITY vào score
        (ưu tiên cao hơn, nhưng chỉ thắng nếu không quá lệch tâm).
        """
        pool = []
        for k in range(1, len(tokens)):
            sp        = tok_starts[k]
            left_len  = sp
            right_len = total_len - sp
            if left_len <= 0 or right_len <= 0:
                continue
            if left_len > char_limit or right_len > char_limit:
                continue
            if not is_split_safe_boundary(tokens[k - 1], tokens[k]):
                continue
            if is_atomic_broken(sp):
                continue
            score = abs(sp - ideal)
            if tokens[k - 1]["surface"] in WRAP_PUNCT:
                score -= WRAP_PUNCT_PRIORITY   # ưu tiên sau dấu câu
            pool.append((score, sp))
        return min(pool)[1] if pool else None

    # Pass 1 — strict: cả 2 dòng ≤ max_chars
    best = find_best(max_chars)
    # Pass 2 — nới 4 ký tự nếu không tìm được điểm hợp lệ
    if best is None:
        best = find_best(max_chars + 4)
    # Hard fallback — tìm token boundary gần giữa nhất,
    # ít nhất không để Kinsoku HEAD đứng đầu dòng 2
    if best is None:
        best = min(int(ideal), max_chars)
        best_dist = abs(best - ideal)
        for k in range(1, len(tokens)):
            sp = tok_starts[k]
            if sp <= 0 or sp >= total_len:
                continue
            if tokens[k]["surface"] in KINSOKU_HEAD_PROHIBITED:
                continue
            dist = abs(sp - ideal)
            if dist < best_dist:
                best_dist = dist
                best = sp

    return text[:best] + "\n" + text[best:]


def main():
    w_blocks = read_whisper_srt(sys.argv[1])
    sentences = clean_and_split_script(sys.argv[2])
    output_srt_path = sys.argv[3]

    w_chars = []
    for b in w_blocks:
        norm = normalize_for_matching(b["text"])
        cnt = len(norm)
        if cnt == 0:
            continue
        dur = b["end"] - b["start"]
        for idx, ch in enumerate(norm):
            t_start = b["start"] + (idx / cnt) * dur
            t_end   = b["start"] + ((idx + 1) / cnt) * dur  # = b["end"] when cnt==1
            w_chars.append({"char": ch, "time": t_start, "time_end": t_end})

    str_w = "".join(x["char"] for x in w_chars)
    c_char_map = []
    str_c_list = []
    for idx, sent in enumerate(sentences):
        norm = normalize_for_matching(sent)
        for ch in norm:
            c_char_map.append(idx)
            str_c_list.append(ch)
    str_c = "".join(str_c_list)

    matcher = difflib.SequenceMatcher(None, str_c, str_w)
    matching_blocks = matcher.get_matching_blocks()

    sent_norm_times     = {i: [] for i in range(len(sentences))}
    sent_norm_end_times = {i: [] for i in range(len(sentences))}
    for match in matching_blocks:
        c_start, w_start, match_len = match
        for k in range(match_len):
            wc = w_chars[w_start + k]
            si = c_char_map[c_start + k]
            sent_norm_times[si].append(wc["time"])
            sent_norm_end_times[si].append(wc["time_end"])

    raw_render = []
    for i, sent in enumerate(sentences):
        norm_times     = sent_norm_times[i]
        norm_end_times = sent_norm_end_times[i]
        phys_times     = []
        phys_time_ends = []
        n_idx = 0
        for ch in sent:
            if re.match(r"[。、！？「」『』（）\s\n\-―]", ch):
                prev_t  = phys_times[-1]     if phys_times     else 0.0
                prev_te = phys_time_ends[-1] if phys_time_ends else 0.0
                phys_times.append(prev_t + 0.01)
                phys_time_ends.append(prev_te + 0.01)
            else:
                if n_idx < len(norm_times):
                    t = norm_times[n_idx]
                    te = norm_end_times[n_idx]
                else:
                    # Kịch bản dài hơn Whisper — ngoại suy theo MAX_CPS
                    t = (phys_times[-1] + 1.0 / MAX_CPS) if phys_times else 0.0
                    te = t + 1.0 / MAX_CPS
                phys_times.append(t)
                phys_time_ends.append(te)
                n_idx += 1

        raw_render.extend(split_sentence_by_physical_times(sent, phys_times, phys_time_ends, MAX_DURATION))

    raw_render = merge_tail_fragments(raw_render)

    final_blocks = []
    for text, start, end in raw_render:
        if end - start < MIN_DURATION:
            end = start + MIN_DURATION
        if final_blocks and start - final_blocks[-1][2] < MIN_GAP:
            start = final_blocks[-1][2] + MIN_GAP
        if final_blocks and start < final_blocks[-1][2]:
            start = final_blocks[-1][2] + MIN_GAP
        if end <= start:
            end = start + MIN_DURATION
        final_blocks.append((text, start, end))

    # Triệt tiêu dấu câu rớt đầu Timecode (、。――・) — bốc ngược TEXT vào block liền trước
    # KHÔNG kéo dài end_time của block trước (sẽ tạo overlap).
    LEADING_PUNCT = {"、", "。", "――", "・"}
    cleaned_blocks = []
    for text, start, end in final_blocks:
        stripped = text
        while stripped and stripped[0] in LEADING_PUNCT:
            if cleaned_blocks:
                prev_text, prev_start, prev_end = cleaned_blocks[-1]
                # Chỉ dán text, giữ nguyên end_time — tránh tạo overlap
                cleaned_blocks[-1] = (prev_text + stripped[0], prev_start, prev_end)
            stripped = stripped[1:].lstrip()
        if stripped:
            cleaned_blocks.append((stripped, start, end))
        # Nếu toàn bộ text là dấu câu đã bốc hết → bỏ block này
    final_blocks = cleaned_blocks

    # Phát hiện và tái phân bổ timing cho cluster CPS không khả thi
    # (xảy ra khi Whisper bị drift ở đoạn B-roll/nhạc nền → dồn nhiều câu vào 8s)
    final_blocks = redistribute_cps_clusters(final_blocks)
    final_blocks = finalize_block_timings(final_blocks)

    # Ngắt dòng cho DaVinci Resolve — SRT hiển thị \n nguyên văn
    final_blocks = [(wrap_text_mecab(text), start, end) for text, start, end in final_blocks]
    final_blocks = finalize_block_timings(final_blocks)

    with open(output_srt_path, "w", encoding="utf-8") as out:
        for idx, (text, start, end) in enumerate(final_blocks, 1):
            out.write(f"{idx}\n{format_srt_time(start)} --> {format_srt_time(end)}\n{text}\n\n")


if __name__ == "__main__":
    main()
