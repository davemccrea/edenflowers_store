defmodule EdenflowersWeb.Admin.CoursesLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  use Oban.Testing, repo: Edenflowers.Repo

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Plug.Helpers

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn}
  end

  test "lists confirmed bookings with seat counts, hides unpaid ones and shows cancelled ones apart", %{conn: conn} do
    course = generate(course(name: "Autumn wreaths", total_places: 10))

    generate(
      course_registration(course_id: course.id, status: :confirmed, name: "Anna", email: "anna@example.com", seats: 3)
    )

    generate(course_registration(course_id: course.id, status: :pending, name: "Pending Pete"))
    generate(course_registration(course_id: course.id, status: :cancelled, name: "Cancelled Carl"))

    {:ok, view, html} = live(conn, ~p"/admin/courses")

    assert html =~ "Autumn wreaths"
    assert html =~ "3 / 10 seats"
    assert has_element?(view, "li", "Anna")
    assert has_element?(view, "li", "+2")
    assert has_element?(view, ~s|a[href="https://app.fastmail.com/mail/compose?bcc=anna%40example.com"]|)
    refute html =~ "Pending Pete"
    assert has_element?(view, ".line-through", "Cancelled Carl")
  end

  test "cancelling a booking moves it to the cancelled list", %{conn: conn} do
    registration = generate(course_registration(status: :confirmed, name: "Anna"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    view |> element(~s|button[phx-click="cancel"][phx-value-id="#{registration.id}"]|) |> render_click()

    assert has_element?(view, ".line-through", "Anna")
    refute has_element?(view, ~s|button[phx-value-id="#{registration.id}"]|)
    assert Ash.get!(Edenflowers.Courses.CourseRegistration, registration.id, authorize?: false).status == :cancelled
  end

  test "adds a booking that pays at the course and emails a confirmation", %{conn: conn} do
    course = generate(course(name: "Autumn wreaths", total_places: 10))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    view |> element(~s|button[phx-value-course-id="#{course.id}"]|) |> render_click()

    view
    |> form("#booking-form-#{course.id}",
      form: %{name: "Birgitta", email: "birgitta@example.com", seats: "2", locale: "sv-FI"}
    )
    |> render_submit()

    assert has_element?(view, "li", "Birgitta")
    assert has_element?(view, "li", "Pays at course")
    assert render(view) =~ "2 / 10 seats"
    assert render(view) =~ "1 still to pay at the course"
    assert_enqueued(worker: Edenflowers.Courses.Workers.SendCourseConfirmationEmail)
  end

  test "marking a booking paid clears it from the still-to-pay list", %{conn: conn} do
    registration = generate(course_registration(status: :confirmed, name: "Birgitta"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    view |> element(~s|button[phx-click="mark_paid"][phx-value-id="#{registration.id}"]|) |> render_click()

    refute has_element?(view, "li", "Pays at course")
    refute render(view) =~ "still to pay"
  end

  test "removing a seat shrinks the booking and frees the seat", %{conn: conn} do
    course = generate(course(total_places: 10))

    registration =
      generate(course_registration(course_id: course.id, status: :confirmed, seats: 3, amount: Decimal.new("255.00")))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    view |> element(~s|button[phx-click="remove_seat"][phx-value-id="#{registration.id}"]|) |> render_click()

    assert render(view) =~ "2 / 10 seats"
    reloaded = Ash.get!(Edenflowers.Courses.CourseRegistration, registration.id, authorize?: false)
    assert reloaded.seats == 2
    assert Decimal.equal?(reloaded.amount, "170.00")
  end
end
