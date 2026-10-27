defmodule EdenflowersWeb.MonthGrid do
  @moduledoc """
  A month of days with month navigation and keyboard support. The caller
  draws each day, and optionally the weekday headers and a column before
  each week, through slots.

  The grid owns the month on screen: its month buttons and `CalendarHook`'s
  `"keydown"` and `"client-error"` events come back here. `CalendarHook` moves
  focus between the days with the arrow keys, as one Tab stop.

  Events from the caller's buttons have no `phx-target`, so they go to the
  LiveView, not to this component.

  ## Assigns

    * `:id` (required)
    * `:today` (required)
    * `:focus_date` - when it changes, the grid shows its month
    * `:status` - said after the month whenever the grid changes
    * `:class` - added to the root

  ## Slots

    * `:day` (required) - a day of the month on screen, given
      `%{date: Date.t(), attrs: keyword}`. Spread `attrs` on the day's button,
      as `CalendarHook` needs them: `<button {day.attrs}>`.
    * `:weekday` - a weekday header, given a date on that weekday. Without it,
      the headers are plain labels.
    * `:week` - a column before each week, given the week's seven dates.
    * `:footer` - below the grid, given the first of the month on screen.
  """
  use EdenflowersWeb, {:live_component, gettext_domain: "shared"}

  require Logger

  alias EdenflowersWeb.MonthGrid.Keymap

  @impl true
  def update(assigns, socket) do
    {focus_date, assigns} = Map.pop(assigns, :focus_date)

    socket =
      socket
      |> assign(status: nil, class: nil, weekday: [], week: [], footer: [])
      |> assign(assigns)
      |> assign_new(:view_date, fn %{today: today} -> focus_date || today end)

    socket =
      if focus_date && focus_date != socket.assigns[:focus_date],
        do: assign(socket, view_date: focus_date, focus_date: focus_date),
        else: assign(socket, focus_date: focus_date)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    month = Date.beginning_of_month(assigns.view_date)
    assigns = assign(assigns, month: month, weeks: weeks(month))

    ~H"""
    <div
      id={@id}
      class={["bg-base-100 select-none", @class]}
      phx-hook=".CalendarHook"
      data-view-date={Date.to_iso8601(@view_date)}
      data-focusable-dates={focusable_dates_json(@month)}
    >
      <div role="status" aria-live="polite" aria-atomic="true" class="sr-only">
        {Localize.DateTime.to_string!(@month, format: "LLLL y")}{if @status, do: ". #{@status}"}
      </div>

      <div class="flex items-center justify-between">
        <button
          id={"#{@id}-previous-month"}
          type="button"
          phx-click="show-month"
          phx-target={@myself}
          phx-value-date={Date.shift(@view_date, month: -1)}
          disabled={@month == Date.beginning_of_month(@today)}
          class="size-11 text-base-content -ml-3 flex flex-none cursor-pointer items-center justify-center hover:text-base-content/60 disabled:text-base-content/20 disabled:cursor-default"
        >
          <span class="sr-only">{~t"Previous month"}</span>
          <.icon name="hero-chevron-left" class="h-5 w-5" />
        </button>
        <button
          id={"#{@id}-current-month"}
          type="button"
          phx-click="show-month"
          phx-target={@myself}
          phx-value-date={@today}
          class="min-h-11 px-3"
        >
          {Localize.DateTime.to_string!(@month, format: "LLLL y")}
          <span class="sr-only">, {~t"go to current month"}</span>
        </button>
        <button
          id={"#{@id}-next-month"}
          type="button"
          phx-click="show-month"
          phx-target={@myself}
          phx-value-date={Date.shift(@view_date, month: 1)}
          class="text-base-content size-11 -mr-3 flex flex-none items-center justify-center hover:text-base-content/60"
        >
          <span class="sr-only">{~t"Next month"}</span>
          <.icon name="hero-chevron-right" class="h-5 w-5" />
        </button>
      </div>

      <div
        aria-hidden={if @weekday == [], do: "true"}
        class={["border-base-content/20 mt-2 grid border-b text-center text-sm leading-6", columns(@week)]}
      >
        <span :if={@week != []} aria-hidden="true"></span>
        <%= for date <- List.first(@weeks) do %>
          <span :if={@weekday == []}>{Localize.DateTime.to_string!(date, format: "EEEEEE")}</span>
          {render_slot(@weekday, date)}
        <% end %>
      </div>

      <div id={"#{@id}-grid"} class="mt-1 flex flex-col gap-0.5">
        <div :for={week <- @weeks} class={["grid", columns(@week)]}>
          {render_slot(@week, week)}
          <%= for date <- week do %>
            <%= if Date.beginning_of_month(date) == @month do %>
              {render_slot(@day, %{date: date, attrs: day_attrs(@id, date, @today)})}
            <% else %>
              <div aria-hidden="true" class="aspect-square"></div>
            <% end %>
          <% end %>
        </div>
      </div>

      {render_slot(@footer, @month)}

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CalendarHook">
        /**
         * Navigate the calendar with the keyboard without a round trip to the server for each key press.
         * If the user tries to navigate to a date outside the visible month then the keydown event is
         * forwarded to the server and the server re-renders the view.
         *
         * Wire protocol (server <-> hook):
         *   - data-view-date           : ISO date of the currently focused cell
         *   - data-focusable-dates     : JSON array of ISO dates focusable client-side (current month)
         *   - data-key-targets (cell)  : JSON map { "ArrowUp": "2026-05-05", ... } of the date each
         *                                key would navigate to from this cell
         */
        const NAV_KEYS = [
          "ArrowUp",
          "ArrowDown",
          "ArrowLeft",
          "ArrowRight",
          "Home",
          "End",
          "PageUp",
          "PageDown",
        ];

        export default {
          mounted() {
            if (!this.validateRequirements()) return;

            this.setTabIndex(this.viewDate);

            this.calendarGrid.addEventListener("keydown", (event) => {
              // Bail on modifier-key combos so browser/SR shortcuts (Ctrl+Home,
              // Shift+Arrow, etc.) still reach the host.
              if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) {
                return;
              }
              if (!NAV_KEYS.includes(event.key)) return;
              // Only intercept when a day button is the actual focus target — keeps
              // arrow keys passing through to anything else nested in the grid.
              if (!event.target.closest(`[id^="${this.id}-day-"]`)) return;
              event.preventDefault();
              this.handleKeyDown(event.key);
            });
          },

          updated() {
            this.focusableDates = this.getFocusableDates() || [];

            // Arrow keys within the month move focus without telling the server, so
            // a re-render for anything else still carries the old view date. Only a
            // view date the server changed replaces the client's.
            const serverViewDate = this.getViewDate();
            if (serverViewDate !== this.serverViewDate) {
              this.serverViewDate = serverViewDate;
              this.viewDate = serverViewDate;
            }
            this.setTabIndex(this.viewDate);

            // If the server just moved the view date in response to a cross-month
            // keyboard nav, restore DOM focus to the newly-promoted cell. Doing this
            // here (instead of in a pushEventTo callback) avoids racing the morph:
            // updated() runs after the patch has landed, so the target cell exists.
            if (this.pendingKeyboardNav) {
              this.pendingKeyboardNav = false;
              this.clientFocus(this.viewDate);
            }
          },

          /** @param {string} key */
          handleKeyDown(key) {
            // If focusable dates are missing/empty, every nav would otherwise fall
            // through to serverFocus and spam the server on each keypress.
            if (!this.focusableDates.length) return;

            // A server roundtrip is already in flight (held-key repeat across a month
            // boundary). Drop the event rather than queueing — the user can resume
            // navigating once focus lands on the newly-promoted cell.
            if (this.pendingKeyboardNav) return;

            // Read targets from the currently-focused cell, not the root: each cell's
            // targets are relative to its own date (ArrowDown from May 1 -> May 8,
            // ArrowDown from May 8 -> May 15, etc).
            const viewDateEl = this.getElement(`${this.id}-day-${this.viewDate}`);
            if (!viewDateEl) return;

            const targets = this.parseKeyTargets(viewDateEl);
            if (!targets) return;

            const nextDate = targets[key];
            if (!nextDate) {
              this.error(
                `Key '${key}' missing from data-key-targets on view date element.`,
              );
              return;
            }

            // A date not in data-focusable-dates is the server's to move to.
            if (!this.isClientFocusable(nextDate)) {
              return this.serverFocus(key);
            }

            this.clientFocus(nextDate);
            this.setTabIndex(nextDate);
            this.viewDate = nextDate;
          },

          /**
           * @param {Element} el
           * @returns {Object<string, string> | null}
           */
          parseKeyTargets(el) {
            const raw = el.getAttribute("data-key-targets");
            if (!raw) {
              this.error(
                "Attribute 'data-key-targets' is missing on view date element.",
              );
              return null;
            }

            try {
              return JSON.parse(raw);
            } catch (error) {
              this.error(`Failed to parse 'data-key-targets': ${error.message}`);
              return null;
            }
          },

          /** @param {string} date */
          clientFocus(date) {
            if (!date) {
              this.error("Cannot focus on null date.");
              return;
            }

            const dateEl = this.getElement(`${this.id}-day-${date}`);
            if (dateEl) {
              /** @type {HTMLElement} */ (dateEl).focus();
            }
          },

          /**
           * Used when the focus is to be moved to a date that is not focusable by the client.
           * The server will rerender into the new month; updated() then restores DOM
           * focus to the newly-promoted view date via the `pendingKeyboardNav` flag.
           * @param {string} key
           */
          serverFocus(key) {
            this.pendingKeyboardNav = true;
            this.pushEventTo(this.el, "keydown", { key, viewDate: this.viewDate });
          },

          /**
           * Only one gridcell within the calendar grid is in the tab sequence at a time.
           * @param {string | null} nextDate
           */
          setTabIndex(nextDate = null) {
            const viewDateEl = this.getElement(`${this.id}-day-${this.viewDate}`);
            if (viewDateEl) {
              viewDateEl.setAttribute("tabindex", "-1");
            }

            if (nextDate) {
              const nextDateEl = this.getElement(`${this.id}-day-${nextDate}`);
              if (nextDateEl) {
                nextDateEl.setAttribute("tabindex", "0");
              }
            }
          },

          /** @returns {boolean} */
          validateRequirements() {
            this.id = this.el.getAttribute("id");
            if (!this.id) {
              this.error("Element must have an 'id' attribute.");
              return false;
            }

            this.viewDate = this.getViewDate();
            this.serverViewDate = this.viewDate;
            if (!this.viewDate) {
              this.error(`Attribute 'data-view-date' is required.`);
              return false;
            }

            this.focusableDates = this.getFocusableDates();
            if (this.focusableDates === null) {
              this.error("Attribute 'data-focusable-dates' is required.");
              return false;
            }
            if (!this.focusableDates.length) {
              this.error("Attribute 'data-focusable-dates' must not be empty.");
              return false;
            }

            this.calendarGrid = this.el.querySelector(`#${this.id}-grid`);
            if (!this.calendarGrid) {
              this.error(`Calendar grid with id '${this.id}-grid' not found.`);
              return false;
            }

            return true;
          },

          /**
           * @param {string} id
           * @returns {Element | null}
           */
          getElement(id) {
            const element = document.getElementById(id);
            if (!element) {
              this.error(`Element with id "${id}" not found.`);
            }
            return element;
          },

          /**
           * A focusable date is a date within the current month.
           * @param {string | null} date
           * @returns {boolean}
           */
          isClientFocusable(date) {
            if (!date) return false;
            return this.focusableDates.includes(date);
          },

          getFocusableDates() {
            const focusableDatesAttr = this.el.getAttribute("data-focusable-dates");
            // Distinguish "attribute missing" (null) from "parsed but empty" ([]) so
            // validateRequirements can emit a single error for the missing-attr case.
            if (!focusableDatesAttr) return null;

            try {
              return JSON.parse(focusableDatesAttr);
            } catch (error) {
              this.error(`Failed to parse 'data-focusable-dates': ${error.message}`);
              return [];
            }
          },

          /** @returns {string | null} */
          getViewDate() {
            return this.el.getAttribute("data-view-date");
          },

          /**
           * Logs to the console and forwards the error to the server.
           * @param {string} message
           */
          error(message) {
            console.error(`CalendarHook Error: ${message}`);
            this.pushEventTo(this.el, "client-error", { message: message });
          },
        };
      </script>
    </div>
    """
  end

  @impl true
  def handle_event("show-month", %{"date" => date}, socket) do
    {:noreply, assign(socket, view_date: Date.from_iso8601!(date))}
  end

  def handle_event("keydown", %{"key" => key, "viewDate" => view_date}, socket) do
    date = view_date |> Date.from_iso8601!() |> Keymap.next_date(key, socket.assigns.today)
    {:noreply, assign(socket, view_date: date)}
  end

  def handle_event("client-error", %{"message" => message}, socket) do
    Logger.error("Client error on calendar #{socket.assigns.id}: #{message}")
    {:noreply, socket}
  end

  defp columns([] = _week_slot), do: "grid-cols-7 gap-0.5"
  defp columns(_week_slot), do: "grid-cols-[2rem_repeat(7,_1fr)] gap-0.5 sm:gap-x-1"

  defp day_attrs(id, date, today) do
    [id: "#{id}-day-#{date}", "data-key-targets": Keymap.targets_json(date, today), tabindex: "-1"]
  end

  defp weeks(month) do
    first = Date.beginning_of_week(month)
    last = month |> Date.end_of_month() |> Date.end_of_week()

    first |> Date.range(last) |> Enum.chunk_every(7)
  end

  # The dates the hook moves focus to without asking the server.
  defp focusable_dates_json(month) do
    month
    |> Date.range(Date.end_of_month(month))
    |> Enum.map(&Date.to_iso8601/1)
    |> Jason.encode!()
  end
end
