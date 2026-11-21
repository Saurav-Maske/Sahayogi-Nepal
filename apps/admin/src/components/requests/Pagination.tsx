interface Props { page: number; total: number; pageSize: number; onPage: (p: number) => void }

export default function Pagination({ page, total, pageSize, onPage }: Props) {
  const pages = Math.max(1, Math.ceil(total / pageSize));
  const from = total ? (page - 1) * pageSize + 1 : 0;
  const to = Math.min(total, page * pageSize);

  const nums: (number | '…')[] = [];
  for (let p = 1; p <= pages; p++) {
    if (p === 1 || p === pages || Math.abs(p - page) <= 1) nums.push(p);
    else if (nums[nums.length - 1] !== '…') nums.push('…');
  }

  return (
    <div className="pager">
      <span>Showing {from}–{to} of {total.toLocaleString('en-US')} requests</span>
      <nav aria-label="Pagination">
        <button disabled={page <= 1} onClick={() => onPage(page - 1)}>‹ Previous</button>
        {nums.map((n, i) =>
          n === '…' ? <span key={`e${i}`}>…</span> : (
            <button key={n} className={n === page ? 'is-current' : ''} aria-current={n === page ? 'page' : undefined} onClick={() => onPage(n)}>{n}</button>
          ))}
        <button disabled={page >= pages} onClick={() => onPage(page + 1)}>Next ›</button>
      </nav>
    </div>
  );
}