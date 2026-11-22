import type { ReactNode } from 'react';

type Variant = 'warning' | 'info' | 'validation';
const icons: Record<Variant, string> = { warning: '!', info: 'i', validation: '!' };

export default function FeedbackNotice({ variant, title, children, className = '' }: { variant: Variant; title: string; children: ReactNode; className?: string }) {
  return <section className={`feedback-notice feedback-notice--${variant} ${className}`.trim()} role={variant === 'validation' ? 'alert' : 'status'}>
    <span className="feedback-notice__icon" aria-hidden="true">{icons[variant]}</span>
    <div><strong>{title}</strong><div className="feedback-notice__message">{children}</div></div>
  </section>;
}
