defmodule EdenflowersWeb.Admin.Components do
  use EdenflowersWeb, :html

  attr :count, :integer, required: true
  attr :active, :boolean, required: true

  def count_badge(assigns) do
    ~H"""
    <span class={[
      "text-sm font-semibold tabular-nums px-2 py-0.5 rounded-full",
      if(@active, do: "bg-primary/10 text-primary", else: "bg-base-300/60 text-base-content/65")
    ]}>
      {@count}
    </span>
    """
  end

  attr :category, :atom, default: nil

  @doc "Neutral tag for an expense category. Humanises the enum and renders an em-dash when unset."
  def category_badge(assigns) do
    ~H"""
    <span :if={@category} class="badge badge-soft badge-sm badge-neutral whitespace-nowrap">
      {humanize_category(@category)}
    </span>
    <span :if={is_nil(@category)} class="text-base-content/30" aria-hidden="true">—</span>
    """
  end

  defp humanize_category(category) do
    category |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  attr :confidence, :atom, required: true

  @doc "Extraction-confidence pill, shared by the expenses table and detail view."
  def confidence_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-soft badge-sm capitalize",
      case @confidence do
        :low -> "badge-error"
        :medium -> "badge-warning"
        :high -> "badge-success"
        _ -> "badge-ghost"
      end
    ]}>
      <span
        :if={@confidence == :low}
        class="inline-block size-1.5 rounded-full bg-current"
        aria-hidden="true"
      />
      {@confidence}
    </span>
    """
  end

  attr :width, :string, default: "wide", values: ~w(wide narrow full)
  slot :inner_block, required: true

  @doc """
  Page shell for admin screens: owns horizontal/vertical padding and the
  content max-width so individual LiveViews don't each invent their own.

  `width` is a semantic choice, not a measurement:
    * `wide`   — dashboards, calendars, anything multi-column
    * `narrow` — focused single-record views (detail/edit)
    * `full`   — data tables that should use the whole canvas
  """
  def admin_page(assigns) do
    ~H"""
    <div class={[
      "px-8 py-8",
      case @width do
        "wide" -> "max-w-4xl"
        "narrow" -> "max-w-2xl"
        "full" -> nil
      end
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :title, :string, required: true
  attr :count, :integer, default: nil, doc: "shown as a count badge beside the title"
  slot :inner_block, required: true

  @doc """
  Surface shell for a dashboard widget. Owns the card treatment (border,
  radius, padding) and the title row so every widget agrees on its frame —
  the *content* is free to differ.
  """
  def widget(assigns) do
    ~H"""
    <section class="bg-base-100 border border-base-300/70 rounded-lg p-5">
      <div class="flex items-start justify-between mb-4">
        <h2 class="text-base font-semibold text-base-content">{@title}</h2>
        <.count_badge :if={@count != nil} count={@count} active={@count > 0} />
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :title, :string, required: true
  attr :back, :string, default: nil, doc: "path for a back-navigation link"
  attr :back_label, :string, default: nil
  slot :subtitle, doc: "supporting text rendered under the title, inside the header rule"
  slot :actions

  def admin_page_header(assigns) do
    ~H"""
    <header class="mb-8 pb-6 border-b border-base-300/70">
      <div :if={@back} class="mb-4">
        <.link navigate={@back} class="inline-flex items-center gap-1 text-xs text-base-content/65 hover:text-base-content transition-colors">
          <.icon name="hero-chevron-left" class="h-3 w-3" />
          {@back_label || "Back"}
        </.link>
      </div>
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h1 class="font-sans text-2xl font-semibold text-base-content tracking-tight">{@title}</h1>
          <p :if={@subtitle != []} class="mt-1.5 text-sm leading-relaxed text-base-content/65">
            {render_slot(@subtitle)}
          </p>
        </div>
        <div :if={@actions != []} class="flex items-center gap-2 shrink-0 mt-0.5">
          {render_slot(@actions)}
        </div>
      </div>
    </header>
    """
  end
end
