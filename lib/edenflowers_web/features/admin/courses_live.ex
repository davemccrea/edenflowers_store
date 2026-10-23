defmodule EdenflowersWeb.Admin.CoursesLive do
  @moduledoc """
  Admin list of courses, including capacity and booking status.
  """

  use EdenflowersWeb, :live_view
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Courses.Course
  alias Edenflowers.Format
  alias Edenflowers.Translations
  alias EdenflowersWeb.Admin.DefaultTableView
  alias EdenflowersWeb.Layouts

  # Upcoming courses and past ones still to settle, soonest first.
  @default_view %{"period" => "current", "sort" => "date"}

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: EdenflowersWeb.Endpoint.subscribe("admin:bookings")

    {:ok,
     socket
     |> assign(:page_title, ~t"Courses")
     |> assign(:locale, Localize.get_locale())
     |> assign(:today, Edenflowers.ShopTime.today())}
  end

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply, DefaultTableView.handle_params(params, uri, socket, @default_view)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={~t"Courses"}>
          <:actions>
            <.button href={~q"/#{language}/courses"} target="_blank" variant="secondary" size="sm">
              <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" /> {~t"View in store"}
            </.button>
            <.button navigate={~p"/admin/courses/new"} variant="primary" size="sm">
              <.icon name="hero-plus" class="h-4 w-4" />
              {~t"New course"}
            </.button>
          </:actions>
        </.admin_page_header>

        <Cinder.collection
          id="courses-table"
          resource={Course}
          action={:admin_list}
          actor={@current_user}
          url_state={@url_state}
          sort_mode="exclusive"
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          theme={EdenflowersWeb.Admin.CinderTheme}
          click={fn course -> JS.navigate(~p"/admin/courses/#{course.id}") end}
        >
          <:col :let={course} field="name" label={~t"Name"}>
            <.link
              navigate={~p"/admin/courses/#{course.id}"}
              class="max-w-28 inline-block truncate align-middle font-medium hover:underline sm:max-w-none"
            >
              {Translations.translate(course).name}
            </.link>
          </:col>
          <:col :let={course} field="date" sort={[cycle: [:asc, :desc]]} label={~t"Date"}>
            <span class="whitespace-nowrap tabular-nums">{Format.date(course.date, @locale)}</span>
          </:col>
          <:col :let={course} label={~t"Time"} class="max-sm:hidden">
            <span class="whitespace-nowrap tabular-nums">
              {Format.time(course.start_time, @locale)}–{Format.time(course.end_time, @locale)}
            </span>
          </:col>
          <:col :let={course} label={~t"Seats"} class="text-right max-sm:hidden">
            <span class="whitespace-nowrap tabular-nums">{course.seats_booked} / {course.total_places}</span>
          </:col>
          <:col
            :let={course}
            field="period"
            filter={[
              type: :select,
              label: ~t"When",
              prompt: ~t"All",
              options: [{~t"Current", :current}, {pgettext("course", "Past"), :past}]
            ]}
            label={~t"Status"}
          >
            <span class="flex flex-wrap gap-1">
              <.badge :if={Date.before?(course.date, @today)} tone={:tag}>{pgettext("course", "Past")}</.badge>
              <.badge :if={course.to_settle?} tone={:warning}>{~t"To settle"}</.badge>
            </span>
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "admin:bookings"}, socket),
    do: {:noreply, Cinder.refresh_table(socket, "courses-table")}

  def handle_info(_message, socket), do: {:noreply, socket}
end
