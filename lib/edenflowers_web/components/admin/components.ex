defmodule EdenflowersWeb.Admin.Components do
  use EdenflowersWeb, :html

  attr :count, :integer, required: true
  attr :active, :boolean, required: true

  def count_badge(assigns) do
    ~H"""
    <span class={[
      "text-sm font-semibold tabular-nums px-2 py-0.5 rounded-full",
      if(@active, do: "bg-primary/10 text-primary", else: "bg-base-300/60 text-base-content/40")
    ]}>
      {@count}
    </span>
    """
  end

  attr :title, :string, required: true
  attr :back, :string, default: nil, doc: "path for a back-navigation link"
  attr :back_label, :string, default: nil
  slot :actions

  def admin_page_header(assigns) do
    ~H"""
    <header class="mb-8 pb-6 border-b border-base-300/70">
      <div :if={@back} class="mb-4">
        <.link navigate={@back} class="inline-flex items-center gap-1 text-xs text-base-content/40 hover:text-base-content/70 transition-colors">
          <.icon name="hero-chevron-left" class="h-3 w-3" />
          {@back_label || "Back"}
        </.link>
      </div>
      <div class="flex items-start justify-between gap-4">
        <h1 class="font-sans text-2xl font-semibold text-base-content tracking-tight">{@title}</h1>
        <div :if={@actions != []} class="flex items-center gap-2 shrink-0 mt-0.5">
          {render_slot(@actions)}
        </div>
      </div>
    </header>
    """
  end
end
