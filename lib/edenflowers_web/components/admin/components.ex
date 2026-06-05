defmodule EdenflowersWeb.Admin.Components do
  use EdenflowersWeb, :html

  attr :count, :integer, required: true
  attr :active, :boolean, required: true

  def count_badge(assigns) do
    ~H"""
    <span class={["rounded-full px-2 py-0.5 text-sm font-semibold tabular-nums", if(@active, do: "bg-primary/10 text-primary", else: "bg-base-300/60 text-base-content/65")]}>
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
    <span class={["badge badge-soft badge-sm capitalize", confidence_badge_class(@confidence)]}>
      <span
        :if={@confidence == :low}
        class="size-1.5 inline-block rounded-full bg-current"
        aria-hidden="true"
      />
      {@confidence}
    </span>
    """
  end

  attr :status, :atom, required: true

  @doc "Payment-status pill for an order: paid reads as success, failed as error, refunds and pending stay neutral."
  def payment_status_badge(assigns) do
    ~H"""
    <span class={["badge badge-soft badge-sm whitespace-nowrap capitalize", payment_status_badge_class(@status)]}>
      {@status}
    </span>
    """
  end

  attr :status, :atom, required: true

  @doc "Fulfillment-status pill for an order: fulfilled reads as success, pending stays neutral."
  def fulfillment_status_badge(assigns) do
    ~H"""
    <span class={["badge badge-soft badge-sm whitespace-nowrap capitalize", fulfillment_status_badge_class(@status)]}>
      {@status}
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
    <div class={["px-4 py-5 sm:px-6 sm:py-6 lg:px-8 lg:py-8", admin_page_width_class(@width)]}>
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
    <section class="bg-base-100 border-base-300/70 rounded-lg border p-4 sm:p-5">
      <div class="mb-4 flex items-start justify-between gap-3">
        <h2 class="text-base-content text-base font-semibold">{@title}</h2>
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
    <header class="border-base-300/70 mb-6 pb-5 sm:mb-8 sm:pb-6">
      <div :if={@back} class="mb-4">
        <.link
          navigate={@back}
          class="text-base-content/65 inline-flex items-center gap-1 text-xs transition-colors hover:text-base-content"
        >
          <.icon name="hero-chevron-left" class="h-3 w-3" />
          {@back_label || "Back"}
        </.link>
      </div>
      <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div class="min-w-0">
          <h1 class="font-sans text-base-content text-xl font-semibold tracking-tight sm:text-2xl">
            {@title}
          </h1>
          <p :if={@subtitle != []} class="text-base-content/65 mt-1.5 text-sm leading-relaxed">
            {render_slot(@subtitle)}
          </p>
        </div>
        <div :if={@actions != []} class="flex flex-wrap items-center gap-2 sm:mt-0.5 sm:shrink-0 sm:justify-end">
          {render_slot(@actions)}
        </div>
      </div>
    </header>
    """
  end

  defp confidence_badge_class(:low), do: "badge-error"
  defp confidence_badge_class(:medium), do: "badge-warning"
  defp confidence_badge_class(:high), do: "badge-success"
  defp confidence_badge_class(_), do: "badge-ghost"

  defp payment_status_badge_class(:paid), do: "badge-success"
  defp payment_status_badge_class(:failed), do: "badge-error"
  defp payment_status_badge_class(:refunded), do: "badge-warning"
  defp payment_status_badge_class(_), do: "badge-ghost"

  defp fulfillment_status_badge_class(:fulfilled), do: "badge-success"
  defp fulfillment_status_badge_class(_), do: "badge-ghost"

  defp admin_page_width_class("wide"), do: "max-w-4xl"
  defp admin_page_width_class("narrow"), do: "max-w-2xl"
  defp admin_page_width_class("full"), do: nil
end
