import { useEffect, useMemo, useRef, useState } from 'react';

const toDate = (value: string) => {
  const [year, month, day] = value.split('-').map(Number);
  return new Date(year, month - 1, day);
};
const toValue = (date: Date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
const inputDateLabel = (date: Date) => `${String(date.getMonth() + 1).padStart(2, '0')}/${String(date.getDate()).padStart(2, '0')}/${date.getFullYear()}`;
const monthLabel = new Intl.DateTimeFormat('en', { month: 'long', year: 'numeric' });
const dayLabel = new Intl.DateTimeFormat('en', { day: 'numeric', month: 'short', year: 'numeric' });

interface Props { label: string; value: string; onChange: (value: string) => void; min?: string; max?: string }

export default function DatePicker({ label, value, onChange, min, max }: Props) {
  const selected = value ? toDate(value) : null;
  const [open, setOpen] = useState(false);
  const [month, setMonth] = useState(() => selected ?? new Date());
  const root = useRef<HTMLDivElement>(null);
  const days = useMemo(() => {
    const first = new Date(month.getFullYear(), month.getMonth(), 1);
    const start = new Date(first);
    start.setDate(1 - ((first.getDay() + 6) % 7));
    return Array.from({ length: 42 }, (_, index) => {
      const date = new Date(start);
      date.setDate(start.getDate() + index);
      return date;
    });
  }, [month]);

  useEffect(() => {
    if (!open) return;
    const onPointer = (event: PointerEvent) => { if (!root.current?.contains(event.target as Node)) setOpen(false); };
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape') setOpen(false); };
    document.addEventListener('pointerdown', onPointer);
    document.addEventListener('keydown', onKey);
    return () => { document.removeEventListener('pointerdown', onPointer); document.removeEventListener('keydown', onKey); };
  }, [open]);

  const shiftMonth = (amount: number) => setMonth((current) => new Date(current.getFullYear(), current.getMonth() + amount, 1));
  return <div className="date-picker" ref={root}>
    <span className="date-picker__label">{label}</span>
    <button className="date-picker__trigger" type="button" aria-label={`${label} date${selected ? `: ${dayLabel.format(selected)}` : ''}`} aria-haspopup="dialog" aria-expanded={open} onClick={() => { if (!open && value) setMonth(toDate(value)); setOpen((shown) => !shown); }}>
      <span className="date-picker__value">{selected ? inputDateLabel(selected) : 'MM/DD/YYYY'}</span>
      <span className="date-picker__icon" aria-hidden="true"><svg viewBox="0 0 20 20" fill="none"><rect x="3" y="5" width="14" height="12" rx="2" stroke="currentColor" strokeWidth="1.5"/><path d="M6.5 3.5v3M13.5 3.5v3M3 8.5h14" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/><path d="M6.5 11h2v2h-2z" fill="currentColor"/></svg></span>
    </button>
    {open && <div className="date-picker__popover" role="dialog" aria-label={`${label} calendar`}>
      <div className="date-picker__heading"><button type="button" aria-label="Previous month" onClick={() => shiftMonth(-1)}>‹</button><strong>{monthLabel.format(month)}</strong><button type="button" aria-label="Next month" onClick={() => shiftMonth(1)}>›</button></div>
      <div className="date-picker__grid" role="grid">
        {['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'].map((day) => <span key={day} className="date-picker__weekday" role="columnheader">{day}</span>)}
        {days.map((date) => {
          const key = toValue(date);
          const disabled = Boolean((min && key < min) || (max && key > max));
          const outside = date.getMonth() !== month.getMonth();
          return <button key={key} type="button" role="gridcell" aria-label={dayLabel.format(date)} aria-pressed={key === value} disabled={disabled} className={`${outside ? 'is-outside ' : ''}${key === value ? 'is-selected' : ''}`} onClick={() => { onChange(key); setOpen(false); }}>{date.getDate()}</button>;
        })}
      </div>
      <p className="date-picker__selected">{selected ? `Selected: ${dayLabel.format(selected)}` : 'Select a date'}</p>
      {value && <button className="date-picker__clear" type="button" onClick={() => { onChange(''); setOpen(false); }}>Clear date</button>}
    </div>}
  </div>;
}
