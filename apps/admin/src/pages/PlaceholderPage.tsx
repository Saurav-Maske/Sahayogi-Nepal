export default function PlaceholderPage({ title }: { title: string }) {
  return (
    <>
      <div className="page__head">
        <div>
          <h1>{title}</h1>
          <p className="crumbs">Sahayogi Nepal / {title}</p>
        </div>
      </div>
      <div className="card">
        <p className="empty">This page hasn't been built yet.</p>
      </div>
    </>
  );
}