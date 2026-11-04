defmodule EdenflowersWeb.Admin.ExpenseDetailLive do
  @moduledoc """
  Admin page for reviewing, correcting, marking paid or deleting an imported expense.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Expenses.Expense
  alias Edenflowers.Format
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @loads [:overdue, :scheduled, :needs_review]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Ash.get(Expense, id, load: @loads, actor: socket.assigns.current_user) do
      {:ok, expense} ->
        {:ok,
         socket
         |> assign(:page_title, ~t"Expense: #{expense.vendor_name || id}")
         |> assign(:locale, Localize.get_locale())
         |> assign(:expense, expense)
         |> assign(:form, build_form(expense, socket.assigns.current_user))}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Expense not found.")
         |> push_navigate(to: ~p"/admin/expenses")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header
          title={@expense.vendor_name || ~t"Unknown vendor"}
          back={{~t"Expenses", ~p"/admin/expenses"}}
        >
          <:subtitle>
            <span class="inline-flex flex-wrap items-center gap-2">
              <.expense_payment_status
                :if={is_nil(@expense.paid_on) or @expense.scheduled}
                expense={@expense}
                locale={@locale}
              />
              <.badge :if={@expense.paid_on && !@expense.scheduled} tone={:success} icon="hero-check">
                {~t"Paid #{date = Format.date(@expense.paid_on, @locale)}"}
              </.badge>
              <.badge :if={@expense.needs_review} tone={:attention}>{~t"Needs review"}</.badge>
            </span>
          </:subtitle>
          <:actions>
            <%!-- These submit the form, so corrections typed below are saved with the paid date. --%>
            <.button
              :if={is_nil(@expense.paid_on) and not is_nil(@expense.due_on)}
              type="submit"
              form="expense-form"
              name="scheduled_for_due_date"
              value="true"
              variant="secondary"
              size="sm"
            >
              <.icon name="hero-calendar" class="h-4 w-4" /> {~t"Mark payment scheduled"}
            </.button>
            <.button
              :if={is_nil(@expense.paid_on)}
              type="submit"
              form="expense-form"
              name="paid_today"
              value="true"
              variant="primary"
              size="sm"
            >
              <.icon name="hero-check" class="h-4 w-4" /> {~t"Mark paid"}
            </.button>
          </:actions>
          <:menu :if={@expense.paid_on}>
            <.actions_menu id="expense-actions">
              <.actions_menu_button menu="expense-actions" phx-click="mark_unpaid">
                {~t"Mark unpaid"}
              </.actions_menu_button>
            </.actions_menu>
          </:menu>
        </.admin_page_header>

        <div class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start">
          <.form
            for={@form}
            id="expense-form"
            data-warn-unsaved={~t"You have unsaved changes. Leave without saving?"}
            phx-submit="correct"
            phx-change="validate"
          >
            <.form_section title={~t"Details"}>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input field={@form[:vendor_name]} type="text" label={~t"Vendor name"} class="input w-full" />
                <.input field={@form[:vendor_vat_number]} type="text" label={~t"VAT number"} class="input w-full" />
                <.input field={@form[:date]} type="date" label={~t"Date"} class="input w-full" />
                <.input
                  field={@form[:paid_on]}
                  type="date"
                  label={~t"Paid on"}
                  help={~t"Leave empty while it's unpaid. A future date means the payment is scheduled."}
                  class="input w-full"
                />
                <.input field={@form[:due_on]} type="date" label={~t"Due date"} class="input w-full" />
                <.input
                  field={@form[:currency]}
                  type="select"
                  label={~t"Currency"}
                  options={[EUR: :eur, SEK: :sek]}
                  class="select w-full"
                />
                <.input
                  field={@form[:total_amount]}
                  type="text"
                  inputmode="decimal"
                  label={~t"Total amount"}
                  class="input w-full"
                />
                <.input
                  field={@form[:vat_amount]}
                  type="text"
                  inputmode="decimal"
                  label={~t"VAT amount"}
                  class="input w-full"
                />
                <.input
                  field={@form[:category]}
                  type="select"
                  label={~t"Category"}
                  options={category_options()}
                  class="select w-full"
                />
                <div class="sm:col-span-2">
                  <.input field={@form[:description]} type="textarea" label={~t"Description"} class="textarea w-full" />
                </div>
              </div>
            </.form_section>
            <div class="mt-6">
              <.button type="submit" variant="primary" class="w-full sm:w-auto">
                {~t"Save"}
              </.button>
            </div>
          </.form>

          <aside class="order-first flex flex-col gap-6 xl:order-none">
            <.widget id="expense-summary" title={~t"Total amount"}>
              <p class="text-base-content truncate text-3xl font-semibold tabular-nums tracking-tight">
                <span :if={@expense.total_amount && @expense.currency}>
                  {Format.currency_in(@expense.total_amount, @expense.currency, @locale)}
                </span>
                <.blank :if={is_nil(@expense.total_amount) or is_nil(@expense.currency)} />
                <span :if={is_nil(@expense.total_amount) or is_nil(@expense.currency)} class="sr-only">
                  {~t"No amount"}
                </span>
              </p>
              <p :if={@expense.confidence != :high} class="text-base-content/75 mt-3 flex items-center gap-2 text-sm">
                {~t"Confidence"} <.confidence_badge confidence={@expense.confidence} />
              </p>
            </.widget>

            <.widget id="expense-receipt" title={~t"Receipt"}>
              <div class="space-y-1.5 text-sm">
                <a
                  href={Edenflowers.External.PapraAPI.document_url(@expense.document_id)}
                  target="_blank"
                  rel="noopener"
                  class="link link-primary inline-flex items-center gap-1 font-semibold"
                >
                  {~t"Open receipt in Papra"}
                  <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
                </a>
                <p :if={@expense.processed_at} class="text-base-content/75">
                  {~t"Processed"} {Format.datetime(@expense.processed_at, @locale)}
                </p>
                <p :if={@expense.reviewed_at} class="text-base-content/75">
                  {~t"Reviewed"} {Format.datetime(@expense.reviewed_at, @locale)}
                </p>
              </div>
            </.widget>
          </aside>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("correct", %{"form" => params} = submit_params, socket) do
    params =
      params
      |> Map.put("paid_today", Map.get(submit_params, "paid_today", "false"))
      |> Map.put("scheduled_for_due_date", Map.get(submit_params, "scheduled_for_due_date", "false"))

    case AshPhoenix.Form.submit(socket.assigns.form, params: params, action_opts: [load: @loads]) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign_expense(updated)
         |> push_event("admin-form-saved", %{id: "expense-form"})
         |> put_flash(:success, ~t"Expense updated.")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, ~t"The expense wasn't saved. Check the fields marked below.")}
    end
  end

  def handle_event("mark_unpaid", _params, socket) do
    case Edenflowers.Expenses.mark_expense_unpaid(socket.assigns.expense,
           actor: socket.assigns.current_user,
           load: @loads
         ) do
      {:ok, updated} ->
        {:noreply, socket |> assign_expense(updated) |> put_flash(:success, ~t"Marked unpaid.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, ~t"The expense wasn't marked unpaid.")}
    end
  end

  defp assign_expense(socket, expense) do
    socket
    |> assign(:expense, expense)
    |> assign(:form, build_form(expense, socket.assigns.current_user))
  end

  defp build_form(expense, actor) do
    AshPhoenix.Form.for_update(expense, :correct, actor: actor) |> to_form()
  end
end
