defmodule EdenflowersWeb.Admin.Components do
  use EdenflowersWeb, :html

  alias EdenflowersWeb.Admin.OrderLog

  attr :count, :integer, required: true
  attr :active, :boolean, required: true
  attr :tone, :atom, default: :primary, values: [:primary, :warning]

  def count_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm rounded-full font-semibold tabular-nums", count_badge_class(@active, @tone)]}>
      {@count}
    </span>
    """
  end

  defp count_badge_class(false, _tone), do: "border-0 bg-base-300/60 text-base-content/75"
  defp count_badge_class(true, :primary), do: "border-0 bg-primary/10 text-primary"
  defp count_badge_class(true, :warning), do: "admin-badge-warning"

  attr :tone, :atom, required: true, values: [:success, :warning, :attention, :error, :neutral, :tag]
  attr :icon, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(href type)
  slot :inner_block, required: true

  @doc """
  The one pill every admin badge is drawn with, so they can't drift apart.

  The coloured tones are states; `:tag` is a quieter, borderless fill for
  facts about a record, like its category or that it's a gift.
  """
  def badge(%{rest: %{type: "button"}} = assigns) do
    ~H"""
    <button class={[badge_class(@tone, @class), "touch-target cursor-pointer hover:brightness-95"]} {@rest}>
      <.icon :if={@icon} name={@icon} class="h-3.5 w-3.5 shrink-0" />
      {render_slot(@inner_block)}
    </button>
    """
  end

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

  attr :id, :string, required: true, doc: "the menu's id, which its items name to close it"
  attr :class, :any, default: "w-44", doc: "the menu's width"
  slot :inner_block, required: true, doc: "`actions_menu_button`s, links or other `<li>` items"

  @doc """
  A page's ⋯ "More actions" menu.

  A popover anchored to its trigger rather than a focus dropdown, so it sits in
  the top layer and closes on Esc or a click outside.

  Its trigger always sits at the right edge (the page header's `menu` slot, or
  the end of a row), so the menu opens below it aligned to its right edge. Avoid
  `position-try-fallbacks` for flipping: iOS Safari 26 draws the flipped menu
  without its border and shadow.
  """
  def actions_menu(assigns) do
    ~H"""
    <.icon_button popovertarget={@id} style={"anchor-name: --#{@id}"} size="sm" aria_label={~t"More actions"}>
      <.icon name="hero-ellipsis-horizontal" class="h-5 w-5" />
    </.icon_button>
    <ul
      id={@id}
      popover
      style={"position-anchor: --#{@id}"}
      class={["dropdown dropdown-end menu bg-base-100 border-base-content/12 mt-2 border p-1 shadow", @class]}
    >
      {render_slot(@inner_block)}
    </ul>
    """
  end

  attr :menu, :string, required: true, doc: "id of the `actions_menu` it closes"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @doc """
  An item in an `actions_menu` that closes the menu when chosen. A declined
  `data-confirm` cancels the click, so the menu stays open.
  """
  def actions_menu_button(assigns) do
    ~H"""
    <li>
      <button type="button" popovertarget={@menu} popovertargetaction="hide" class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
    </li>
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

  def fulfillment_method_icon(:delivery), do: "hero-truck"
  def fulfillment_method_icon(:pickup), do: "hero-building-storefront"
  def fulfillment_method_icon(_), do: "hero-question-mark-circle"

  def category_options do
    Edenflowers.Expenses.Expense.Category.values()
    |> Enum.map(fn value -> {category_label(value), value} end)
  end

  def category_label(:flowers_and_plants), do: ~t"Flowers and plants"
  def category_label(:florist_supplies), do: ~t"Florist supplies"
  def category_label(:rent), do: ~t"Rent"
  def category_label(:entertainment), do: ~t"Entertainment"
  def category_label(:bank_fees), do: ~t"Bank fees"
  def category_label(:vehicle), do: ~t"Vehicle"
  def category_label(:travel), do: ~t"Travel"
  def category_label(:marketing), do: ~t"Marketing"
  def category_label(:software), do: ~t"Software"
  def category_label(:utilities), do: ~t"Utilities"
  def category_label(:office_supplies), do: ~t"Office supplies"
  def category_label(:equipment), do: ~t"Equipment"
  def category_label(:insurance), do: ~t"Insurance"
  def category_label(:professional_services), do: ~t"Professional services"
  def category_label(:other), do: ~t"Other"
  def category_label(:unknown), do: ~t"Unknown"
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
  def subscription_state_label(:cancelled), do: pgettext("subscription", "Cancelled")

  defp subscription_state_tone(:active), do: :success
  defp subscription_state_tone(:payment_failed), do: :error
  defp subscription_state_tone(_), do: :neutral

  attr :class, :any, default: nil

  @doc "Marks an Occurrence: an order a Subscription created, not one the customer placed at checkout."
  def subscription_badge(assigns) do
    ~H"""
    <.badge tone={:tag} icon="hero-arrow-path" class={@class}>{~t"Subscription"}</.badge>
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
      class="link link-primary touch-target inline-flex items-center gap-1.5"
      title={~t"Search Fastmail for this address"}
    >
      <.icon name="hero-envelope" class="h-3.5 w-3.5 shrink-0" />
      <span class="break-all">{@email}</span>
    </a>
    """
  end

  attr :name, :string, default: nil
  slot :contact

  def person_block(assigns) do
    ~H"""
    <div class="space-y-1.5">
      <p :if={@name} class="text-base-content text-base font-medium">{@name}</p>
      <div :for={contact <- @contact} class="text-sm">{render_slot(contact)}</div>
    </div>
    """
  end

  attr :phone_number, :string, required: true

  def phone_link(assigns) do
    ~H"""
    <a
      href={"tel:#{@phone_number}"}
      class="link link-primary touch-target inline-flex items-center gap-1.5"
    >
      <.icon name="hero-phone" class="h-3.5 w-3.5 shrink-0" />
      {@phone_number}
    </a>
    """
  end

  attr :order, :map,
    required: true,
    doc: "needs `payment_status`, `settled?`, `amount_paid` and `balance`"

  attr :locale, :string, required: true

  @doc "An order's payment status, or the amount still to collect or refund when it was part-paid or overpaid."
  def order_payment_badge(%{order: order} = assigns) do
    # An order that took nothing yet reads as Unpaid rather than as its total to collect.
    assigns = assign(assigns, :owes_money?, not order.settled? and Decimal.positive?(order.amount_paid))

    ~H"""
    <.badge
      :if={@owes_money?}
      tone={if Decimal.positive?(@order.balance), do: :warning, else: :error}
      class="tabular-nums"
    >
      <%= if Decimal.positive?(@order.balance) do %>
        {~t"To collect #{amount = Edenflowers.Format.currency(@order.balance, @locale)}"}
      <% else %>
        {~t"To refund #{amount = Edenflowers.Format.currency(Decimal.abs(@order.balance), @locale)}"}
      <% end %>
    </.badge>
    <.payment_status_badge :if={!@owes_money?} status={@order.payment_status} />
    """
  end

  attr :id, :string, required: true
  attr :record, :map, required: true, doc: "an order, with `balance` and `settled?` loaded"
  attr :locale, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, doc: "more ways to settle it, like the order page's payment link"

  @doc """
  What's still owed on an order. Hidden once settled. Its button sends
  `open_settlement`, for the page to open a drawer with `record_payment_form`.
  """
  def balance_panel(%{record: %{settled?: true}} = assigns) do
    ~H""
  end

  def balance_panel(assigns) do
    assigns = assign(assigns, :collect?, Decimal.positive?(assigns.record.balance))

    ~H"""
    <div id={@id} class={["border-base-content/12 border-t pt-4", @class]}>
      <p class="text-base-content flex items-baseline justify-between gap-4 text-base font-semibold">
        {if @collect?, do: ~t"To collect", else: ~t"To refund"}
        <span class="tabular-nums">{Edenflowers.Format.currency(Decimal.abs(@record.balance), @locale)}</span>
      </p>

      <div class="mt-3 flex flex-wrap items-center gap-2">
        <.button
          id={"#{@id}-settle"}
          type="button"
          variant="secondary"
          size="sm"
          aria-haspopup="dialog"
          aria-controls="settlement-drawer"
          phx-click="open_settlement"
        >
          <.icon name={if @collect?, do: "hero-banknotes", else: "hero-arrow-uturn-left"} class="h-4 w-4" />
          {if @collect?, do: ~t"Record payment", else: ~t"Record refund"}
        </.button>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :id, :string, required: true

  attr :record, :map,
    required: true,
    doc: "an order, with `balance` and `outside_stripe_refund` loaded"

  attr :locale, :string, required: true
  attr :params, :map, default: %{}, doc: "the payment form as Jennie has filled it in so far"
  attr :receipt_email?, :boolean, default: false, doc: "whether the customer can be emailed a receipt"

  @doc """
  Records money Jennie took or handed back herself. Sends `record_payment` with
  `payment` params and the record's id as `record_id`, and `change_payment` with
  `payment` params as the form is filled in.
  """
  def record_payment_form(assigns) do
    form = balance_form(assigns.record, assigns.params)

    assigns =
      assigns
      |> assign(:collect?, Decimal.positive?(assigns.record.balance))
      |> assign(:form, form)
      |> assign(:settles?, settles?(assigns.record, form[:amount].value))

    ~H"""
    <.form for={@form} id={"#{@id}-form"} phx-change="change_payment" phx-submit="record_payment" class="space-y-4">
      <input type="hidden" name="record_id" value={@record.id} />
      <p :if={!@collect?} class="text-base-content/75 text-sm">
        {~t"Records money you have already handed back. Nothing is sent to the customer."}
      </p>
      <fieldset aria-describedby={if !@collect?, do: "#{@id}-help"} class="space-y-4">
        <div class="grid grid-cols-2 items-end gap-x-3 gap-y-4">
          <.input
            field={@form[:payment_method]}
            id={"#{@id}-method"}
            type="select"
            label={~t"How"}
            class="select w-full"
            options={payment_method_options()}
          />
          <.input
            field={@form[:amount]}
            id={"#{@id}-amount"}
            type="text"
            inputmode="decimal"
            label={~t"Amount (€)"}
            class="input w-full tabular-nums"
          />
        </div>
        <p :if={!@collect?} id={"#{@id}-help"} class="text-base-content/75 text-sm">
          {~t"A minus amount records a refund."}
        </p>
        <.input
          :if={@collect? and @settles? and @receipt_email?}
          field={@form[:email_receipt]}
          id={"#{@id}-email-receipt"}
          type="checkbox"
          label={~t"Email a receipt"}
        />
      </fieldset>
      <.button
        type="submit"
        variant="primary"
        phx-disable-with={~t"Recording…"}
        data-confirm={
          if @collect?,
            do: ~t"Record this payment? A mistake can be undone afterwards.",
            else: ~t"Record this refund? A mistake can be undone afterwards."
        }
      >
        {if @collect?, do: ~t"Record payment", else: ~t"Record refund"}
      </.button>
    </.form>
    """
  end

  defp balance_form(record, params) do
    amount =
      if Decimal.positive?(record.balance),
        do: record.balance,
        else: Decimal.negate(record.outside_stripe_refund)

    %{"payment_method" => "zettle", "amount" => Decimal.to_string(amount, :normal), "email_receipt" => "true"}
    |> Map.merge(params)
    |> to_form(as: :payment)
  end

  defp settles?(record, amount) do
    case Decimal.parse(String.replace(amount, ",", ".")) do
      {amount, ""} -> Decimal.eq?(amount, record.balance)
      _ -> false
    end
  end

  @doc "Every way Jennie records money herself; Stripe records its own."
  def payment_method_options do
    Edenflowers.Payments.PaymentMethod.values()
    |> List.delete(:stripe)
    |> Enum.map(&{OrderLog.payment_method_label(&1), &1})
  end

  @doc "Asks before undoing a payment Jennie recorded, naming it."
  def undo_confirmation(payment, locale) do
    amount = Edenflowers.Format.currency(Decimal.abs(payment.amount), locale)
    how = OrderLog.payment_method_label(payment.method)

    if Decimal.negative?(payment.amount),
      do: ~t"Undo the #{amount} refund by #{how}? This records the opposite amount.",
      else: ~t"Undo the #{amount} payment by #{how}? This records the opposite amount."
  end

  attr :id, :string, required: true

  attr :record, :map,
    required: true,
    doc: "an order or booking, with `paid_through_stripe` and `paid_outside_stripe` loaded"

  attr :locale, :string, required: true
  attr :params, :map, default: %{}, doc: "the form as Jennie has filled it in so far"
  attr :hidden, :boolean, default: true, doc: "false when it's already in view, like in a drawer"
  attr :class, :any, default: nil

  @doc """
  Hands money back to an unhappy customer without lowering what was sold.
  Hidden until something shows it, like a menu's "Refund", unless `hidden` is false. Sends
  `goodwill_refund` with `goodwill_refund` params and the record's id as
  `record_id`, and `change_goodwill_refund` as the form is filled in, so the
  confirmation can name the amount.
  """
  def goodwill_refund_form(assigns) do
    form =
      %{"how" => default_goodwill_method(assigns.record), "amount" => "", "note" => ""}
      |> Map.merge(assigns.params)
      |> to_form(as: :goodwill_refund)

    assigns = assign(assigns, form: form, how_options: goodwill_method_options(assigns.record))

    ~H"""
    <div id={@id} class={[@hidden && "hidden", @class]}>
      <.form
        for={@form}
        id={"#{@id}-form"}
        phx-change="change_goodwill_refund"
        phx-submit="goodwill_refund"
        class="grid grid-cols-2 items-end gap-x-3 gap-y-4"
      >
        <input type="hidden" name="record_id" value={@record.id} />
        <p class="text-base-content col-span-2 text-sm font-medium">{~t"Refund the customer"}</p>
        <.input
          field={@form[:amount]}
          id={"#{@id}-amount"}
          type="text"
          inputmode="decimal"
          label={~t"Amount (€)"}
          class="input w-full tabular-nums"
        />
        <.input
          field={@form[:how]}
          id={"#{@id}-how"}
          type="select"
          label={~t"How"}
          class="select w-full"
          options={@how_options}
        />
        <div class="col-span-2">
          <.input
            field={@form[:note]}
            id={"#{@id}-note"}
            type="text"
            label={~t"Reason (optional)"}
            class="input w-full"
          />
        </div>
        <.button
          type="submit"
          variant="primary"
          class="col-span-2"
          phx-disable-with={~t"Refunding…"}
          data-confirm={goodwill_confirmation(@form[:amount].value, @form[:how].value, @locale)}
        >
          {~t"Refund"}
        </.button>
      </.form>
    </div>
    """
  end

  defp default_goodwill_method(record),
    do: if(Decimal.positive?(record.paid_through_stripe), do: "stripe", else: "zettle")

  # Stripe money goes back through Stripe; money Jennie took herself she hands back herself.
  defp goodwill_method_options(record) do
    stripe = [{OrderLog.payment_method_label(:stripe), :stripe}]

    case {Decimal.positive?(record.paid_through_stripe), Decimal.positive?(record.paid_outside_stripe)} do
      {true, true} -> stripe ++ payment_method_options()
      {true, false} -> stripe
      {false, _} -> payment_method_options()
    end
  end

  defp goodwill_confirmation(amount, how, locale) do
    with {amount, ""} <- Decimal.parse(String.replace(amount || "", ",", ".")),
         true <- Decimal.positive?(amount) do
      amount = Edenflowers.Format.currency(amount, locale)

      if how == "stripe",
        do: ~t"Refund #{amount} to the customer's card with Stripe? The price stays as it is.",
        else: ~t"Record #{amount} handed back to the customer? The price stays as it is."
    else
      _invalid -> nil
    end
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :on_close, JS, default: %JS{}, doc: "runs after the drawer hides, like telling the server"
  slot :inner_block, required: true

  @doc """
  The admin's right-hand drawer: a titled panel with a close button, so every
  admin drawer has one width and one header. Put the content in `drawer_body`
  and any buttons in `drawer_footer`; a form can wrap both.
  Open it with `JS.exec("phx-show", to: "#id")` or the `js-exec` event.
  """
  def admin_drawer(assigns) do
    ~H"""
    <.drawer
      id={@id}
      placement="right"
      label={@title}
      class="bg-base-100 border-base-content/12 w-[88vw] flex h-full flex-col border-l sm:w-[28rem]"
    >
      <header class="border-base-content/12 flex shrink-0 items-center justify-between gap-4 border-b p-4">
        <h2 class="text-lg font-semibold">{@title}</h2>
        <.icon_button
          phx-click={JS.exec("phx-hide", to: "##{@id}") |> JS.concat(@on_close)}
          size="sm"
          aria_label={~t"Close"}
        >
          <.icon name="hero-x-mark" class="h-5 w-5" />
        </.icon_button>
      </header>
      {render_slot(@inner_block)}
    </.drawer>
    """
  end

  slot :inner_block, required: true

  @doc "An `admin_drawer`'s content, which scrolls under the header."
  def drawer_body(assigns) do
    ~H"""
    <div class="flex-1 space-y-5 overflow-y-auto overscroll-contain p-4">
      {render_slot(@inner_block)}
    </div>
    """
  end

  slot :inner_block, required: true

  @doc "An `admin_drawer`'s buttons, pinned to its bottom."
  def drawer_footer(assigns) do
    ~H"""
    <div class="border-base-content/12 flex shrink-0 flex-wrap gap-2 border-t p-4">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :title, :string, required: true
  attr :class, :any, default: nil
  attr :joined, :boolean, default: false, doc: "render inside a shared admin-card with divided sections"
  slot :description
  slot :inner_block, required: true

  @doc "A titled group of fields in an admin form, framed like a `widget` so forms and detail pages match."
  def form_section(assigns) do
    ~H"""
    <section class={["p-4 sm:p-5", !@joined && "admin-card", @class]}>
      <header class="mb-4">
        <h2 class="text-base-content text-base font-semibold">{@title}</h2>
        <p :if={@description != []} class="text-base-content/75 mt-1 text-sm">{render_slot(@description)}</p>
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :label, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def summary_fact(assigns) do
    ~H"""
    <div class={@class}>
      <p class="eyebrow text-base-content/75 mb-1.5">{@label}</p>
      <div class="text-base-content text-base font-medium leading-relaxed">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  slot :inner_block, required: true

  @doc "Page shell for admin screens: owns the padding, so individual LiveViews don't each invent their own."
  def admin_page(assigns) do
    ~H"""
    <div class="px-4 py-5 sm:px-6 sm:py-6 lg:px-8 lg:py-8">
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
    <section id={@id} class={["admin-card p-4 sm:p-5", @class]}>
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
        class="text-base-content/75 shrink-0 text-xs tabular-nums"
      >
        {history_time(@at, @locale)}
      </time>
    </div>
    """
  end

  attr :title, :string, required: true

  attr :back, :any, default: nil, doc: "{label, path} of the page above this one, shown as a back link"
  attr :sticky, :boolean, default: false, doc: "compact persistent header for long admin forms"
  slot :subtitle, doc: "supporting text rendered under the title"
  slot :status, doc: "brief state beside a sticky title, hidden on phones"
  slot :actions
  slot :menu, doc: "the page's `actions_menu`, kept beside the title on phones while the actions wrap below it"
  slot :nav, doc: "sibling navigation rendered opposite the back link"

  def admin_page_header(assigns) do
    ~H"""
    <header
      :if={@sticky}
      class="bg-base-100 border-base-content/12 top-[calc(env(safe-area-inset-top)+4rem)] sticky z-20 -mx-4 -mt-5 mb-6 flex items-center gap-3 border-b px-4 py-2.5 sm:-mx-6 sm:-mt-6 sm:px-6 lg:top-0 lg:-mx-8 lg:-mt-8 lg:mb-8 lg:px-8 lg:py-3"
    >
      <.link
        :if={@back}
        navigate={elem(@back, 1)}
        class="text-base-content/70 -m-2 inline-flex shrink-0 items-center gap-1.5 p-2 text-sm font-medium transition-colors hover:text-base-content"
      >
        <.icon name="hero-arrow-left" class="h-4 w-4" />
        <span class="sr-only">{elem(@back, 0)}</span>
      </.link>
      <h1 class="text-base-content min-w-0 truncate text-lg font-semibold tracking-tight">{@title}</h1>
      <div :if={@status != []} class="shrink-0 max-sm:hidden">{render_slot(@status)}</div>
      <div :if={@actions != [] || @menu != []} class="ml-auto flex shrink-0 items-center gap-2 sm:gap-3">
        {render_slot(@actions)}
        {render_slot(@menu)}
      </div>
    </header>
    <p :if={@sticky && @subtitle != []} class="text-base-content/75 mb-6 text-sm leading-relaxed sm:mb-8">
      {render_slot(@subtitle)}
    </p>
    <header :if={!@sticky} class="mb-6 sm:mb-8">
      <div :if={@back || @nav != []} class="mb-4 flex flex-wrap items-center justify-between gap-x-6 gap-y-4">
        <.link
          :if={@back}
          navigate={elem(@back, 1)}
          class="text-base-content/70 -my-2 inline-flex min-w-0 items-center gap-1.5 py-2 text-sm font-medium transition-colors pointer-coarse:-my-3 pointer-coarse:py-3 hover:text-base-content"
        >
          <.icon name="hero-arrow-left" class="h-4 w-4 shrink-0" />
          <span class="max-w-[14rem] truncate">{elem(@back, 0)}</span>
        </.link>
        {render_slot(@nav)}
      </div>
      <div class="flex items-start gap-2">
        <div class="flex min-w-0 flex-1 flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div class="min-w-0">
            <h1 class="font-sans text-base-content text-xl font-semibold tracking-tight sm:text-2xl">
              {@title}
            </h1>
            <p :if={@subtitle != []} class="text-base-content/75 mt-1.5 text-sm leading-relaxed">
              {render_slot(@subtitle)}
            </p>
          </div>
          <div :if={@actions != []} class="flex flex-wrap items-center gap-2 sm:mt-0.5 sm:shrink-0 sm:justify-end">
            {render_slot(@actions)}
          </div>
        </div>
        <div :if={@menu != []} class="-mt-1 shrink-0 sm:mt-0.5">
          {render_slot(@menu)}
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

  @doc "Only a string with non-whitespace content is present."
  def present?(value), do: is_binary(value) and String.trim(value) != ""

  def presence(value), do: if(present?(value), do: value)

  defp history_time(at, locale) do
    local = DateTime.shift_zone!(at, Edenflowers.ShopTime.timezone())

    "#{Edenflowers.Format.day_month(DateTime.to_date(local), locale)} #{Edenflowers.Format.time(DateTime.to_time(local), locale)}"
  end

  attr :label, :string, required: true
  attr :amount, :any, default: nil
  attr :locale, :string, required: true
  attr :strong, :boolean, default: false
  attr :muted, :boolean, default: false, doc: "for figures already counted in the total, like included VAT"
  attr :ruled, :boolean, default: false, doc: "starts a new group under the rows above"

  @doc "A label and an amount in a list of money, as the order page's Payment section shows them."
  def money_row(assigns) do
    ~H"""
    <div class={["flex items-center justify-between gap-4 py-0.5", @ruled && "border-base-content/12 mt-1.5 border-t pt-2", @strong && "border-base-content/12 text-base-content mt-1.5 border-t pt-3 font-semibold", @muted && "text-base-content/75"]}>
      <dt class={money_row_tone(@strong, @muted, "text-base-content/75")}>
        {@label}
      </dt>
      <dd class={["tabular-nums", money_row_tone(@strong, @muted, "text-base-content/90")]}>
        {Edenflowers.Format.currency(@amount, @locale)}
      </dd>
    </div>
    """
  end

  defp money_row_tone(true = _strong, _muted, _default), do: "text-base-content"
  defp money_row_tone(_strong, true = _muted, _default), do: nil
  defp money_row_tone(_strong, _muted, default), do: default
end
