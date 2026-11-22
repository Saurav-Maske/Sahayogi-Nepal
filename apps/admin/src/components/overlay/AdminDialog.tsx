import { useEffect, useId, useRef, type ReactNode } from "react";
import { createPortal } from "react-dom";

export type DialogAction = {
  label: string;
  onClick: () => void;
  variant?: "primary" | "danger" | "secondary";
  disabled?: boolean;
};

export default function AdminDialog({
  open,
  title,
  description,
  onClose,
  children,
  actions,
  size = "regular",
}: {
  open: boolean;
  title: string;
  description?: string;
  onClose: () => void;
  children?: ReactNode;
  actions?: DialogAction[];
  size?: "regular" | "wide";
}) {
  const titleId = useId();
  const descriptionId = useId();
  const closeRef = useRef<HTMLButtonElement>(null);
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;

  useEffect(() => {
    if (!open) return;
    const previousFocus = document.activeElement as HTMLElement | null;
    const dialog = closeRef.current?.closest("[role='dialog']");
    (dialog?.querySelector<HTMLElement>("[autofocus]") ?? closeRef.current)?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onCloseRef.current();
      if (event.key !== "Tab") return;
      const activeDialog = closeRef.current?.closest("[role='dialog']");
      const controls = activeDialog?.querySelectorAll<HTMLElement>(
        "button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea:not(:disabled), a[href]",
      );
      if (!controls?.length) return;
      const first = controls[0];
      const last = controls[controls.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      previousFocus?.focus();
    };
  }, [open]);

  if (!open) return null;
  return createPortal(
    <div className="admin-overlay" onMouseDown={(event) => event.target === event.currentTarget && onClose()}>
      <section
        className={`admin-dialog${size === "wide" ? " admin-dialog--wide" : ""}`}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={description ? descriptionId : undefined}
      >
        <header className="admin-dialog__head">
          <div>
            <h2 id={titleId}>{title}</h2>
            {description && <p id={descriptionId}>{description}</p>}
          </div>
          <button ref={closeRef} type="button" className="admin-dialog__close" onClick={onClose} aria-label="Close dialog">×</button>
        </header>
        {children && <div className="admin-dialog__body">{children}</div>}
        {actions && actions.length > 0 && <footer className="admin-dialog__actions">
          {actions.map((action) => <button
            type="button"
            key={action.label}
            className={`btn${action.variant === "primary" ? " btn--primary" : action.variant === "danger" ? " btn--danger" : ""}`}
            onClick={action.onClick}
            disabled={action.disabled}
          >{action.label}</button>)}
        </footer>}
      </section>
    </div>,
    document.body,
  );
}
