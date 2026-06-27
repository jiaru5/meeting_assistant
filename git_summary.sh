#!/usr/bin/env bash

git log --since="30 days ago" --numstat --pretty="__DATE__%ad" --date=short \
| awk -v BAR_WIDTH=20 '
# 仅捕获日期行
/^__DATE__[0-9]{4}-[0-9]{2}-[0-9]{2}$/ {
  date = substr($0, 9)
  next
}

# 仅捕获 numstat 行：added<TAB>deleted<TAB>path
/^[0-9-]+\t[0-9-]+\t/ && date != "" {
  a = $1; d = $2
  if (a == "-") a = 0
  if (d == "-") d = 0
  add[date] += a
  del[date] += d
  next
}

function repeat(ch, n,   s, i) { s=""; for (i=0; i<n; i++) s=s ch; return s }
function line() { print "+------------+--------------+--------------+--------------+" repeat("-", BAR_WIDTH) }

END {
  # 先算 max daily total（强度归一化）
  max_t = 0
  for (i=30; i>=0; i--) {
    cmd = "date -v-" i "d +%Y-%m-%d"
    cmd | getline dstr
    close(cmd)
    t = (add[dstr]+0) + (del[dstr]+0)
    if (t > max_t) max_t = t
  }

  total_add = 0
  total_del = 0

  line()
  printf "| %-10s | %12s | %12s | %12s | %s\n", \
         "Date", "TotalChanged", "Added", "Deleted", "Bar (█ add / ░ del)"
  line()

  for (i=30; i>=0; i--) {
    cmd = "date -v-" i "d +%Y-%m-%d"
    cmd | getline dstr
    close(cmd)

    a = add[dstr]+0
    b = del[dstr]+0
    t = a + b

    total_add += a
    total_del += b

    # 条形长度（0..BAR_WIDTH）：按当天总变更相对 max day 缩放
    len = (max_t > 0) ? int((t / max_t) * BAR_WIDTH + 0.5) : 0

    # 在 len 内按新增/删除占比切分
    if (t > 0 && len > 0) {
      n_add = int((a / t) * len + 0.5)
      if (n_add > len) n_add = len
      n_del = len - n_add
    } else {
      n_add = 0; n_del = 0
    }

    bar = repeat("█", n_add) repeat("░", n_del)
    bar = bar repeat(" ", BAR_WIDTH - length(bar))

    printf "| %-10s | %12d | %12d | %12d | %s\n", dstr, t, a, b, bar
  }

  line()

  # TOTAL 行：用满宽 BAR_WIDTH，按总新增/总删除占比切分
  T = total_add + total_del
  if (T > 0) {
    nA = int((total_add / T) * BAR_WIDTH + 0.5)
    if (nA > BAR_WIDTH) nA = BAR_WIDTH
    nD = BAR_WIDTH - nA
  } else { nA = 0; nD = 0 }

  total_bar = repeat("█", nA) repeat("░", nD)
  total_bar = total_bar repeat(" ", BAR_WIDTH - length(total_bar))

  printf "| %-10s | %12d | %12d | %12d | %s\n", "TOTAL", T, total_add, total_del, total_bar
  line()
}
'
