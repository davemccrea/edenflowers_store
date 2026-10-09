defmodule EdenflowersWeb.Admin.Components do
  use EdenflowersWeb, :html

  attr :count, :integer, required: true
  attr :active, :boolean, required: true

  defp count_badge(assigns) do
    ~H"""
    <span class={["rounded-full px-2 py-0.5 text-sm font-semibold tabular-nums", if(@active, do: "bg-primary/10 text-primary", else: "bg-base-300/60 text-base-content/65")]}>
      {@count}
    </span>
    """
  end

  attr :tone, :atom, required: true, values: [:success, :warning, :attention, :error, :neutral, :tag]
  attr :icon, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(href)
  slot :inner_block, required: true

  @doc """
  The one pill every admin badge is drawn with, so they can't drift apart.

  The coloured tones are states; `:tag` is a quieter, borderless fill for
  facts about a record, like its category or that it's a gift.
  """
  def badge(%{rest: %{href: _}} = assigns) do
    ~H"""
    <a class={badge_class(@tone, @class)} {@rest}>
      <.icon :if={@icon} name={@icon} class="h-3.5 w-3.5 shrink-0" />
      {render_slot(@inner_block)}
    </a>
    """
  end

  def badge(assigns) do
    ~H"""
    <span class={badge_class(@tone, @class)} {@rest}>
      <.icon :if={@icon} name={@icon} class="h-3.5 w-3.5 shrink-0" />
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp badge_class(tone, class),
    do: ["badge badge-sm inline-flex items-center gap-1 whitespace-nowrap", badge_tone_class(tone), class]

  defp badge_tone_class(:success), do: "admin-badge-success"
  defp badge_tone_class(:warning), do: "admin-badge-warning"
  defp badge_tone_class(:attention), do: "admin-badge-attention"
  defp badge_tone_class(:error), do: "admin-badge-error"
  defp badge_tone_class(:neutral), do: "admin-badge-neutral"
  defp badge_tone_class(:tag), do: "badge-soft badge-neutral"

  attr :category, :atom, default: nil

  @doc "Neutral tag for an expense category. Humanises the enum and renders an em-dash when unset."
  def category_badge(assigns) do
    ~H"""
    <.badge :if={@category} tone={:tag}>{category_label(@category)}</.badge>
    <.blank :if={is_nil(@category)} />
    """
  end

  attr :id, :string, required: true
  attr :target, :string, required: true, doc: "selector of the element whose text or value is copied"
  attr :label, :string, required: true
  attr :size, :string, default: "sm", values: ~w(xs sm)
  attr :class, :any, default: nil

  @doc "Icon button that copies `target` and turns into a tick once it has."
  def copy_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click={JS.dispatch("edenflowers:copy", to: @target, detail: %{trigger: "##{@id}"})}
      class={["btn btn-ghost btn-square group shadow-none", if(@size == "xs", do: "btn-xs", else: "btn-sm"), @class]}
      title={@label}
      aria-label={@label}
    >
      <.icon name="hero-clipboard" class="h-4 w-4 group-data-copied:hidden" />
      <.icon name="hero-check" class="text-success hidden h-4 w-4 group-data-copied:inline-block" />
      <span class="sr-only" aria-live="polite">
        <span class="hidden group-data-copied:inline">{~t"Copied"}</span>
      </span>
    </button>
    """
  end

  attr :recipient_name, :string, default: nil

  @doc "Marks a gift order, naming who it's for when the customer said."
  def gift_badge(assigns) do
    ~H"""
    <.badge
      tone={:tag}
      icon="hero-gift"
      title={if @recipient_name, do: ~t"Gift for #{order_recipient_name = @recipient_name}", else: ~t"Gift order"}
    >
      <span :if={@recipient_name} class="max-w-[10rem] truncate">{~t"For #{name = @recipient_name}"}</span>
      <span :if={is_nil(@recipient_name)}>{~t"Gift"}</span>
    </.badge>
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
    <.badge tone={confidence_tone(@confidence)}>
      <span
        :if={@confidence == :low}
        class="inline-block h-1.5 w-1.5 rounded-full bg-current"
        aria-hidden="true"
      />
      {confidence_label(@confidence)}
    </.badge>
    """
  end

  attr :status, :atom, required: true, doc: "nil shows a dash, for a payment status with nothing to say"

  @doc """
  Payment-status pill for an order: paid reads as success, refunded as attention,
  failed as error. Pending reads as "Unpaid": admin only sees placed orders, and
  a placed order still pending is a custom order waiting for its money.
  """
  def payment_status_badge(%{status: nil} = assigns) do
    ~H"""
    <.blank />
    """
  end

  def payment_status_badge(assigns) do
    ~H"""
    <.badge tone={payment_status_tone(@status)}>{payment_status_label(@status)}</.badge>
    """
  end

  attr :status, :atom, required: true

  @doc "Fulfillment-status pill for an order: fulfilled reads as success, cancelled as error, pending stays neutral."
  def fulfillment_status_badge(assigns) do
    ~H"""
    <.badge tone={fulfillment_status_tone(@status)}>{fulfillment_status_label(@status)}</.badge>
    """
  end

  attr :state, :atom, required: true

  def subscription_state_badge(assigns) do
    ~H"""
    <.badge tone={subscription_state_tone(@state)}>{subscription_state_label(@state)}</.badge>
    """
  end

  def subscription_state_label(:active), do: ~t"Active"
  def subscription_state_label(:paused), do: ~t"Paused"
  def subscription_state_label(:payment_failed), do: ~t"Payment failed"
  def subscription_state_label(:cancelled), do: ~t"Cancelled"

  defp subscription_state_tone(:active), do: :success
  defp subscription_state_tone(:payment_failed), do: :error
  defp subscription_state_tone(_), do: :neutral

  @doc "Marks an Occurrence: an order a Subscription created, not one the customer placed at checkout."
  def subscription_badge(assigns) do
    ~H"""
    <.badge tone={:tag} icon="hero-arrow-path">{~t"Subscription"}</.badge>
    """
  end

  attr :email, :string, required: true

  @doc "A customer's email address, linked to a Fastmail search for their correspondence."
  def email_link(assigns) do
    ~H"""
    <a
      href={"https://app.fastmail.com/mail/search:#{URI.encode_www_form(to_string(@email))}"}
      target="_blank"
      rel="noopener"
      class="link link-primary inline-flex items-center gap-1.5"
      title={~t"Search Fastmail for this address"}
    >
      <.icon name="hero-envelope" class="h-3.5 w-3.5 shrink-0" />
      <span class="break-all">{@email}</span>
    </a>
    """
  end

  attr :title, :string, required: true
  attr :class, :any, default: nil
  slot :description
  slot :inner_block, required: true

  @doc "A titled group of fields in an admin form, set off from the previous group by a rule."
  def form_section(assigns) do
    ~H"""
    <section class={["border-base-content/12 border-t pt-6 first:border-t-0 first:pt-0", @class]}>
      <header class="mb-4">
        <h2 class="text-base-content text-base font-semibold">{@title}</h2>
        <p :if={@description != []} class="text-base-content/65 mt-1 text-sm">{render_slot(@description)}</p>
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  def summary_fact(assigns) do
    ~H"""
    <div>
      <p class="eyebrow text-base-content/65 mb-1.5">{@label}</p>
      <div class="text-base-content text-base font-medium leading-relaxed">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :width, :string, default: "wide", values: ~w(wide narrow full)
  slot :inner_block, required: true

  @doc """
  Page shell for admin screens: owns horizontal/vertical padding and the
  content max-width so individual LiveViews don't each invent their own.

  `width` is a semantic choice, not a measurement:
    * `wide`   — dashboards, calendars, and multi-column detail or edit views
    * `narrow` — single-column forms, details, and card lists
    * `full`   — data tables, capped so rows stay scannable on very wide screens
  """
  def admin_page(assigns) do
    ~H"""
    <div class={["px-4 py-5 sm:px-6 sm:py-6 lg:px-8 lg:py-8", admin_page_width_class(@width)]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :count, :integer, default: nil, doc: "shown as a count badge beside the title"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  @doc """
  Surface shell for a dashboard widget. Owns the card treatment (border,
  radius, padding) and the title row so every widget agrees on its frame —
  the *content* is free to differ.
  """
  def widget(assigns) do
    ~H"""
    <section id={@id} class={["bg-base-100 border-base-content/12 border p-4 sm:p-5", @class]}>
      <div class="mb-4 flex items-start justify-between gap-3">
        <h2 class="text-base-content text-base font-semibold">{@title}</h2>
        <.count_badge :if={@count != nil} count={@count} active={@count > 0} />
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :at, DateTime, required: true
  attr :locale, :string, required: true
  slot :details

  def history_entry(assigns) do
    ~H"""
    <li class="py-2 first:pt-0 last:pb-0">
      <.history_heading :if={@details == []} title={@title} at={@at} locale={@locale} />
      <details
        :if={@details != []}
        id={@id}
        phx-mounted={JS.ignore_attributes(["open"])}
        class="group"
      >
        <summary class="cursor-pointer list-none">
          <.history_heading title={@title} at={@at} locale={@locale} expandable />
        </summary>
        {render_slot(@details)}
      </details>
    </li>
    """
  end

  attr :title, :string, required: true
  attr :at, DateTime, required: true
  attr :locale, :string, required: true
  attr :expandable, :boolean, default: false

  defp history_heading(assigns) do
    ~H"""
    <div class="flex items-baseline justify-between gap-4">
      <p class="text-base-content flex items-center gap-1 font-medium">
        {@title}
        <.icon
          :if={@expandable}
          name="hero-chevron-right"
          class="text-base-content/50 h-3.5 w-3.5 transition-transform group-open:rotate-90"
        />
      </p>
      <time
        datetime={DateTime.to_iso8601(@at)}
        title={Edenflowers.Format.datetime(@at, @locale)}
        class="text-base-content/65 shrink-0 text-xs tabular-nums"
      >
        {history_time(@at, @locale)}
      </time>
    </div>
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

  defp confidence_tone(:low), do: :error
  defp confidence_tone(:medium), do: :warning
  defp confidence_tone(:high), do: :success
  defp confidence_tone(_), do: :neutral

  def confidence_options do
    Edenflowers.Expenses.Expense.Confidence.values()
    |> Enum.map(fn value -> {confidence_label(value), value} end)
  end

  # Context keeps "Medium" apart from the variant size, which translates differently.
  defp confidence_label(:low), do: pgettext("expense confidence", "Low")
  defp confidence_label(:medium), do: pgettext("expense confidence", "Medium")
  defp confidence_label(:high), do: pgettext("expense confidence", "High")
  defp confidence_label(value), do: to_string(value)

  defp payment_status_tone(:paid), do: :success
  defp payment_status_tone(:refunded), do: :attention
  defp payment_status_tone(:pending), do: :warning
  defp payment_status_tone(_), do: :neutral

  defp payment_status_label(:paid), do: ~t"Paid"
  defp payment_status_label(:refunded), do: ~t"Refunded"
  defp payment_status_label(:pending), do: ~t"Unpaid"
  defp payment_status_label(value), do: to_string(value)

  defp fulfillment_status_tone(:fulfilled), do: :success
  defp fulfillment_status_tone(:cancelled), do: :error
  defp fulfillment_status_tone(_), do: :neutral

  defp fulfillment_status_label(:fulfilled), do: ~t"Fulfilled"
  defp fulfillment_status_label(:pending), do: ~t"Pending"
  defp fulfillment_status_label(:cancelled), do: ~t"Cancelled"
  defp fulfillment_status_label(value), do: to_string(value)

  defp history_time(at, locale) do
    local = DateTime.shift_zone!(at, "Europe/Helsinki")

    "#{Edenflowers.Format.day_month(DateTime.to_date(local), locale)} #{Edenflowers.Format.time(DateTime.to_time(local), locale)}"
  end

  defp admin_page_width_class("wide"), do: "max-w-6xl"
  defp admin_page_width_class("narrow"), do: "max-w-2xl"
  defp admin_page_width_class("full"), do: "max-w-7xl"
end
