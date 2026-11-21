import { STATUS_LABEL, STATUS_TONE } from '../../utils/requests';
import { humanize } from '../../utils/labels';

export default function StatusBadge({ status }: { status: string }) {
  return <span className={`badge badge--${STATUS_TONE[status] ?? 'muted'}`}>{STATUS_LABEL[status] ?? humanize(status)}</span>;
}