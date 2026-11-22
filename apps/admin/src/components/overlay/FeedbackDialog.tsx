import AdminDialog from "./AdminDialog";

export default function FeedbackDialog({
  feedback,
  onClose,
}: {
  feedback: { title: string; message: string } | null;
  onClose: () => void;
}) {
  return <AdminDialog
    open={feedback !== null}
    title={feedback?.title ?? "Done"}
    description={feedback?.message}
    onClose={onClose}
    actions={[{ label: "Done", variant: "primary", onClick: onClose }]}
  />;
}
