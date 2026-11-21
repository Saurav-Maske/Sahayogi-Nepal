import { STATUS_LABEL, STATUS_TONE } from '../../utils/requests';
import { humanize } from '../../utils/labels';

interface Props { status: string; labels?: Record<string, string> }

export default function StatusBadge({ status, labels = STATUS_LABEL }: Props) {
  return <span className={`badge badge--${STATUS_TONE[status] ?? 'muted'}`}>{labels[status] ?? humanize(status)}</span>;
}