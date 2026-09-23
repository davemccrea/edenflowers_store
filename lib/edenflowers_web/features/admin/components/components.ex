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
      {category_label(@category)}
    </span>
    <.blank :if={is_nil(@category)} />
    """
  end

  @doc "Placeholder for an empty table value. Hidden from screen readers, which would otherwise read out \"em dash\"."
  def blank(assigns) do
    ~H"""
    <span class="text-base-content/30" aria-hidden="true">—</span>
    """
  end

  attr :method, :atom, required: true
  attr :label, :string, default: nil, doc: "overrides the method name, e.g. with the fulfillment option's own name"
  attr :class, :any, default: nil

  def fulfillment_method(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-1.5 whitespace-nowrap", @class]}>
      <.icon name={fulfillment_method_icon(@method)} class="text-base-content/60 h-[1.2em] w-[1.2em] shrink-0" />
      {@label || fulfillment_method_label(@method)}
    </span>
    """
  end

  def fulfillment_method_label(:delivery), do: ~t"Delivery"
  def fulfillment_method_label(:pickup), do: ~t"Pickup"
  def fulfillment_method_label(_), do: ~t"Unknown method"

  def variant_size_label(:small), do: ~t"Small"
  def variant_size_label(:medium), do: ~t"Medium"
  def variant_size_label(:large), do: ~t"Large"
  def variant_size_label(value), do: to_string(value)

  defp fulfillment_method_icon(:delivery), do: "hero-truck"
  defp fulfillment_method_icon(:pickup), do: "hero-building-storefront"
  defp fulfillment_method_icon(_), do: "hero-question-mark-circle"

  def category_options do
    Edenflowers.Expenses.Expense.Category.values()
    |> Enum.map(fn value -> {category_label(value), value} end)
  end

  def category_label(:office_supplies), do: ~t"Office supplies"
  def category_label(:travel), do: ~t"Travel"
  def category_label(:meals), do: ~t"Meals"
  def category_label(:software), do: ~t"Software"
  def category_label(:marketing), do: ~t"Marketing"
  def category_label(:utilities), do: ~t"Utilities"
  def category_label(:professional_services), do: ~t"Professional services"
  def category_label(:other), do: ~t"Other"
  def category_label(value), do: to_string(value)

  attr :confidence, :atom, required: true

  @doc "Extraction-confidence pill, shared by the expenses table and detail view."
  def confidence_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm capitalize", confidence_badge_class(@confidence)]}>
      <span
        :if={@confidence == :low}
        class="inline-block h-1.5 w-1.5 rounded-full bg-current"
        aria-hidden="true"
      />
      {confidence_label(@confidence)}
    </span>
    """
  end

  attr :status, :atom, required: true

  @doc "Payment-status pill for an order: paid reads as success, refunded as attention, failed as error, pending stays neutral."
  def payment_status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm whitespace-nowrap capitalize", payment_status_badge_class(@status)]}>
      {payment_status_label(@status)}
    </span>
    """
  end

  attr :status, :atom, required: true

  @doc "Fulfillment-status pill for an order: fulfilled reads as success, pending stays neutral."
  def fulfillment_status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm whitespace-nowrap capitalize", fulfillment_status_badge_class(@status)]}>
      {fulfillment_status_label(@status)}
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
    <section class="bg-base-100 border-base-content/12 border p-4 sm:p-5">
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
  slot :subtitle, doc: "supporting text rendered under the title"
  slot :actions
  slot :nav, doc: "sibling navigation rendered opposite the back link"

  def admin_page_header(assigns) do
    ~H"""
    <header class="mb-8 sm:mb-10">
      <div :if={@back || @nav != []} class="mb-6 flex flex-wrap items-center justify-between gap-x-6 gap-y-4 sm:mb-8">
        <.link
          :if={@back}
          navigate={@back}
          class="text-base-content/80 -my-2 -ml-1 inline-flex items-center gap-1.5 py-2 pr-2 pl-1 text-sm font-medium transition-colors hover:text-base-content"
        >
          <.icon name="hero-arrow-left" class="h-4 w-4" />
          {@back_label || ~t"Back"}
        </.link>
        {render_slot(@nav)}
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

  defp confidence_badge_class(:low), do: "badge-error admin-badge-error"
  defp confidence_badge_class(:medium), do: "badge-warning admin-badge-warning"
  defp confidence_badge_class(:high), do: "badge-success admin-badge-success"
  defp confidence_badge_class(_), do: "admin-badge-neutral"

  def confidence_options do
    Edenflowers.Expenses.Expense.Confidence.values()
    |> Enum.map(fn value -> {confidence_label(value), value} end)
  end

  # Context keeps "Medium" apart from the variant size, which translates differently.
  defp confidence_label(:low), do: pgettext("expense confidence", "Low")
  defp confidence_label(:medium), do: pgettext("expense confidence", "Medium")
  defp confidence_label(:high), do: pgettext("expense confidence", "High")
  defp confidence_label(value), do: to_string(value)

  defp payment_status_badge_class(:paid), do: "badge-success admin-badge-success"
  defp payment_status_badge_class(:failed), do: "badge-error admin-badge-error"
  defp payment_status_badge_class(:refunded), do: "badge-warning admin-badge-attention"
  defp payment_status_badge_class(_), do: "admin-badge-neutral"

  defp payment_status_label(:paid), do: ~t"Paid"
  defp payment_status_label(:failed), do: ~t"Failed"
  defp payment_status_label(:refunded), do: ~t"Refunded"
  defp payment_status_label(:pending), do: ~t"Pending"
  defp payment_status_label(value), do: to_string(value)

  defp fulfillment_status_badge_class(:fulfilled), do: "badge-success admin-badge-success"
  defp fulfillment_status_badge_class(_), do: "admin-badge-neutral"

  defp fulfillment_status_label(:fulfilled), do: ~t"Fulfilled"
  defp fulfillment_status_label(:pending), do: ~t"Pending"
  defp fulfillment_status_label(value), do: to_string(value)

  defp admin_page_width_class("wide"), do: "max-w-4xl"
  defp admin_page_width_class("narrow"), do: "max-w-2xl"
  defp admin_page_width_class("full"), do: nil
end
