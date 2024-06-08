import std/[math, jsffi, dom, jsconsole, enumerate, with, strformat, asyncjs, algorithm]
import karax/[karax, karaxdsl, vdom, vstyles]

import matter, utils

type
  CanonStatus = enum
    csReady # Not launched yet
    csFlight # In the air
    csHit # Hit something and stopped

  CanonState = object
    angleDeg*: int
    angleRad*: float
    speed*: float
    velocity*: tuple[x, y: float]

  Canon = object
    body*: JsObject

    bullets*: seq[JsObject]
    currentBullet*: int
    bulletRadius*: int
    bulletOptions*: JsObject

    trajectory*: seq[JsVector]
    isDragging*: bool # Is the canon being dragged
    status*: CanonStatus
    state*: CanonState

  ParabolaState* = object
    engine*: JsObject
    render*: JsObject
    runner*: JsObject
    canvas*: Element

    paused*: bool

    mouseConstraint*: JsObject
    mouse*: JsObject

    canon*: Canon
    thingy*: JsObject
    ground*: JsObject

proc initCanonState(angleDeg: int, speed: float): CanonState = 
  let angleRad = degToRad(float angleDeg)
  CanonState(angleDeg: angleDeg, angleRad: angleRad, speed: speed, velocity: speedToVelRad(speed, angleRad))

proc initCanonState(angleRad: float, speed: float): CanonState = 
  let angleDeg = int radToDeg(angleRad)
  CanonState(angleDeg: angleDeg, angleRad: angleRad, speed: speed, velocity: speedToVelRad(speed, angleRad))

const
  fps = 60
  delta = 1000 / fps # 60fps, 60 times in one second (1000 milliseconds)
  timeScale = 0.6

  #canvasWidth = 700
  #canvasHeight = 500

  groundHeight = 10

  canonWidth = 120
  canonHeight = 70
  canonX = canonWidth
  canonRotationDeg = 10d
  canonInitialSpeed = 12
  canonTexture = "/public/img/canon.png"
  
  canonBaseImgPath = "/public/img/canonBase.png"

  trajectoryColor = "orange"

  velocityVectorScale = 9

let
  canonBaseImg = newImage()

var
  canonY, canonBaseX, canonBaseY: int
  canonPivot: JsObject

canonBaseImg.src = cstring canonBaseImgPath

proc wrapObject(state: ParabolaState): JsObject = 
  JsObject{min: JsObject{x: 0, y: undefined}, max: JsObject{x: state.canvas.clientWidth, y: undefined}} # To avoid boilerplate

proc onResize(state: var ParabolaState) = 
  state.render.canvas.width = state.canvas.clientWidth
  state.render.canvas.height = state.canvas.clientHeight

  canonY = state.canvas.clientHeight - groundHeight - int(canonBaseImg.height.to(float) * 0.5)
  canonPivot = JsObject{x: canonX  - (canonWidth / 2.5), y: canonY}

  canonBaseX = canonPivot.x.to(int) - canonBaseImg.width.to(int) div 2
  canonBaseY = state.canvas.clientHeight - groundHeight - canonBaseImg.height.to(int)

  Body.setPosition(state.canon.body, JsObject{x: canonX, y: canonY})
  Body.setPosition(state.ground, JsObject{x: state.canvas.clientWidth / 2, y: state.canvas.clientHeight - (groundHeight div 2)})

  let wrap = state.wrapObject()

  state.canon.bulletOptions.plugin = JsObject{wrap: wrap}

  for bullet in state.canon.bullets:
    bullet.plugin.wrap = wrap

  state.thingy.plugin.wrap = wrap

proc initParabolaState*(): ParabolaState = 
  ParabolaState(canon: Canon(
    bulletRadius: 20, state: initCanonState(0, canonInitialSpeed), 
    bulletOptions: JsObject{
      isStatic: false, frictionAir: 0, friction: 1, 
    },
  ))

proc `bullet`(canon: Canon): JsObject = 
  assert canon.currentBullet in canon.bullets.low..canon.bullets.high, &"Invalid bullet index {canon.currentBullet}"
  canon.bullets[canon.currentBullet]

#proc `bullet`(state: var CanonState): var JsObject = 
#  state.bullets[state.currentBullet]

## Since a body's angle can be negative and can be higher than 360, this procedure makes it so it's always positive and inside 0..359
proc normalizeAngle(rad: float): int =
  result = int rad.radToDeg()
  result -= (result div 360) * 360 # Remove excess rotations

  if result < 0:
    result = abs result
  elif result > 0:
    result = 360 - result

proc rotate(canon: var Canon, rad = degToRad(canonRotationDeg)) =
  if normalizeAngle(canon.body.angle.to(float) + rad) notin 20..160:
    return

  Body.rotate(canon.body, rad, canonPivot)

  canon.state.angleDeg = normalizeAngle(canon.body.angle.to(float))
  canon.state.angleRad = degToRad(float canon.state.angleDeg)
  canon.state.velocity = speedToVelRad(canon.state.speed, canon.state.angleRad)

proc rotateBack(canon: var Canon, rad = degToRad(canonRotationDeg)) =
  canon.rotate(-rad)

proc nextBullet(state: var ParabolaState): JsObject = 
  result = Bodies.circle(
    canonPivot.x, canonPivot.y, 
    state.canon.bulletRadius, state.canon.bulletOptions
  )

  Body.setAngle(result, state.canon.state.angleDeg)

proc calcTrajectory(state: var ParabolaState) =
  let bullet = state.nextBullet()
  let gx = to(state.engine.gravity.x * state.engine.gravity.scale, float)
  let gy = to(state.engine.gravity.y * state.engine.gravity.scale, float)
  let v = state.canon.state.velocity

  # Invert velocity y since matter's coordinates start from the top instead of the bottom
  Body.setVelocity(bullet, jsVector(v.x, -v.y))

  state.canon.trajectory.setLen(0)
  var i = 0
  while i < 6000:
    if bullet.position.y.to(int) > state.canvas.clientHeight - groundHeight:
      break

    state.canon.trajectory.add JsVector JsObject{x: jsFloatToInt bullet.position.x, y: jsFloatToInt bullet.position.y}

    bullet.force.x += bullet.mass * toJs gx
    bullet.force.y += bullet.mass * toJs gy
    Body.update(bullet)
    bullet.force.x = 0
    bullet.force.y = 0
    bullet.torque = 0

    inc i

proc loadEvents(state: var ParabolaState) = 
  Events.on(state.mouseConstraint, "mousedown", proc(event: JsObject) = 
    if Bounds.contains(state.canon.body.bounds, event.mouse.position).to(bool):
      state.canon.isDragging = true
  )

  Events.on(state.mouseConstraint, "mouseup", proc(event: JsObject) = 
    state.canon.isDragging = false
  )

  # Set event callbacks
  Events.on(state.engine, "afterUpdate", proc() =
    # So that it updates the formula values
    #if not kxi.surpressRedraws: redraw(kxi) # TODO: REALLY INEFFICIENT
    if state.canon.isDragging:
      let targetAngle = Vector.angle(canonPivot, state.mouse.position)
      state.canon.rotate(to(targetAngle - state.canon.body.angle, float))
      state.calcTrajectory()

      let distance = Vector.sub(canonPivot, state.mouse.position)
      let magnitude = min(max(Vector.magnitude(distance).to(float), 63.0), 163.0)
      echo magnitude
      state.canon.state.speed = (canonInitialSpeed / 120) * magnitude
      state.canon.state.velocity = speedToVelRad(state.canon.state.speed, state.canon.state.angleRad)
  )

  Events.on(state.engine, "collisionStart", proc(event: JsObject) = 
    if state.canon.bullets.len > 0 and state.canon.status == csFlight:
      for pair in items(event.pairs):
        if pair.bodyA.id == state.canon.bullet.id or pair.bodyB.id == state.canon.bullet.id:
          state.canon.status = csHit
          break
  )

  Events.on(state.render, "afterRender", proc() =
    Render.startViewTransform(state.render)

    let ctx = state.render.context

    if canonBaseImg.complete.to(bool):
      ctx.drawImage(canonBaseImg, canonBaseX, canonBaseY)

    if state.canon.bullets.len > 0 and state.canon.status == csFlight:
      let pos = state.canon.bullet.position

      drawArrow(ctx, pos.x, pos.y, 
        pos.x,
        pos.y + (state.canon.bullet.velocity.y * toJs velocityVectorScale), 
        toJs 4, toJs cstring"red"
      )

      drawArrow(ctx, pos.x, pos.y, 
        pos.x + (state.canon.bullet.velocity.x * toJs velocityVectorScale), 
        pos.y,
        toJs 4, toJs cstring"blue"
      )

      #drawArrow(ctx, pos.x, pos.y, 
      #  pos.x + (state.canon.bullet.velocity.x * toJs 9), 
      #  pos.y + (state.canon.bullet.velocity.y * toJs 9), 
      #  toJs 4, toJs cstring"white"
      #)

    ctx.globalAlpha = 0.7

    for p in state.canon.trajectory:
      ctx.fillStyle = cstring trajectoryColor
      ctx.fillRect(JsObject(p).x, JsObject(p).y, 2, 2)

    ctx.globalAlpha = 1

    Render.endViewTransform(state.render)
  )

  ## Sort bodies by z-index/depth
  Events.on(state.engine.world, "afterAdd", proc() =
    state.engine.world.bodies = state.engine.world.bodies.to(seq[JsObject]).sorted(proc(a, b: JsObject): int =
      let z1 = if a.zIndex.isNil: 0 else: a.zIndex.to(int)
      let z2 = if b.zIndex.isNil: 0 else: b.zIndex.to(int)
      z1 - z2
    )
  )

## Loads the simulation
proc load*(state: var ParabolaState) =
  # Render all MathJax expressions asynchronously
  MathJax.typesetPromise()

  # Load wrap's plugin and load matter aliases to point to the correct values
  Matter.use("matter-wrap")
  loadMatterAliases()

  state.canvas = getElementById("canvas")
  state.engine = createEngine(JsObject{gravity: JsObject{x: 0, y: 1, scale: 0.001}, timing: JsObject{timeScale: timeScale}})
  state.render = createRender(JsObject{
    canvas: state.canvas,
    engine: state.engine,
    options: JsObject{
      width: state.canvas.clientWidth,
      height: state.canvas.clientHeight,
      showAngleIndicator: false,
      showSleeping: false,
      wireframes: false,
      background: "transparent",#"rgb(20, 21, 31)",
    }
  })
  Render.run(state.render)

  state.runner = Runner.create(JsObject{delta: delta})
  Runner.run(state.runner, state.engine)

  # Create and add all bodies to the world
  state.canon.body = Bodies.rectangle(canonX, canonY, canonWidth, canonHeight, JsObject{
    zIndex: 1, isStatic: true, collisionFilter: JsObject{mask: 0}, label: cstring"Canon",
    render: JsObject{sprite: JsObject{
      texture: cstring canonTexture, 
      xOffset: 0, yOffset: 0
    }}
  })
  #constraint = Constraint.create(JsObject{pointA: jsVector(0, 0), bodyB: canon})#, length: 30, stiffness: 0.1})

  state.ground = Bodies.rectangle(state.canvas.clientWidth / 2, 
    state.canvas.clientHeight - (groundHeight div 2), state.canvas.clientWidth * 1000, 
    groundHeight, JsObject{zIndex: 10, isStatic: true, label: cstring"Ground"}
  ) # 350, 495, 1200

  state.thingy = Bodies.rectangle(500, 350, 20, 80, JsObject{isStatic: false, label: cstring"Thingy", plugin: JsObject{wrap: state.wrapObject}})

  state.mouse = Mouse.create(state.canvas)
  state.mouseConstraint = MouseConstraint.create(state.engine, JsObject{mouse: state.mouse, collisionFilter: JsObject{mask: 0}})

  state.onResize()
  state.canon.rotateBack(degToRad(60d))

  Composite.add(state.engine.world, toJs [state.canon.body, state.mouseConstraint,
    state.thingy,
    # Walls
     Bodies.rectangle(350, -200, 1000, 20, JsObject{isStatic: true}), # up
    # Bodies.rectangle(690, 250, 20, 500, JsObject{isStatic: true}), # right
    state.ground, # down
    # Bodies.rectangle(10, 250, 20, 500, JsObject{isStatic: true}), # left
  ])

  state.loadEvents()

## Reloads the simulation
proc reload*(state: var ParabolaState) =
  Composite.clear(state.engine.world)
  Engine.clear(state.engine)
  Render.stop(state.render)
  Runner.stop(state.runner)
  state.canon.trajectory.setLen(0)
  state.load()

## Since matter measures y from the top of the screen, here we "normalize" it so that the 0 starts at the ground
proc normalizeY(state: ParabolaState, y: int, height: int): int =
  -y + (state.ground.position.y.to(int) - (groundHeight div 2) - height)

proc fireBullet(state: var ParabolaState) = 
  let bullet = state.nextBullet()

  Composite.add(state.engine.world, bullet)
  state.canon.bullets.add bullet
  state.canon.currentBullet = state.canon.bullets.high

  state.canon.status = csFlight

  let velocity = state.canon.state.velocity

  # Invert velocity y since matter's coordinates start from the top instead of the bottom
  Body.setVelocity(bullet, jsVector(velocity.x, -velocity.y))

proc togglePause(state: var ParabolaState) = 
  if state.paused:
    state.engine.timing.timeScale = timeScale
  else:
    state.engine.timing.timeScale = 0

  state.paused = not state.paused

proc renderTextDiv*(state: ParabolaState): VNode =
  var x, y, angle, speed: int

  if state.canon.bullets.len > 0:
    let bullet = state.canon.bullet

    x = int bullet.position.x.to(float)
    y = state.normalizeY(int bullet.position.y.to(float), bullet.circleRadius.to(int))
    angle = normalizeAngle(bullet.angle.to(float))
    speed = int state.canon.state.speed

  buildHtml tdiv(id = "text", style = "".toCss):
    p(text r"\(t_f = \frac{2 \cdot v_i \cdot \sin(\theta)}{g}\)", style = "font-size: 50px;".toCss)

    p(text &"x = {x} y = {y}")
    p(text &"angle = {angle}")

    p(text &"Vi = {speed}")
    #p(text &"t = {exerciseTotalTime:.2f}")

    # p(text fmt"\(a = \frac{{v_f - {bullet.position.x}}}{{\Delta t}}\)", style = "font-size: 80px;".toCss)

proc renderSimDiv*(state: var ParabolaState): VNode =
  buildHtml tdiv(id = "sim", style = "".toCss):
    button():
      #text "Pause/Resume"
      if state.engine.isNil:
          span(class = "material-symbols-outlined", text "play_pause")
      else:
        if state.paused:
          span(class = "material-symbols-outlined", text "play_arrow")
        else:
          span(class = "material-symbols-outlined", text "pause")

      proc onclick()  =
        state.togglePause()

    button():
      span(class = "material-symbols-outlined", text "rotate_left")
      proc onclick() =
        state.canon.rotateBack()
        state.calcTrajectory()

    button():
      span(class = "material-symbols-outlined", text "rotate_right")
      proc onclick() =
        state.canon.rotate()
        state.calcTrajectory()

    #button():
    #  verbatim parabolaIconSvg
    #  #img(src = "/public/img/parabola.svg", alt = "Parabola Trajectory")
    #  proc onclick() = calcTrajectory()
    #  #text "Trajectory"

    button():
      span(class = "material-symbols-outlined", text "north_east")
      proc onclick() =
        state.fireBullet()

    br()

    canvas(id = "canvas", style = fmt"width: 50vw; min-width: 300px; height: 50vh; min-height: 300px; background: rgb(20, 21, 31)".toCss):
      text "Matter-js simulation"

proc render*(state: var ParabolaState): VNode =
  buildHtml tdiv(style = "display: flex; flex-direction: column; justify-content: start; align-items: center; height: 100%;".toCss):
    state.renderTextDiv()
    state.renderSimDiv()

    #tdiv(id = "exercises-wrapper", style = "flex: 0 0 auto; position: relative; min-width: 50vw;".toCss):
      #tdiv(id = "exercises", style = "position: absolute; top: 0; left: 0; right: 0; bottom: 0; overflow-y: auto;".toCss):
    #tdiv(id = "exercises", style = "flex: 1 1 auto; overflow-y: auto; min-height: 0px;".toCss):
    #  for e, exercise in exercises:
    #    if e == 0: continue # First exercise is the default exercise

    #    tdiv(style = "".toCss):
    #      button(onclick = exerciseOnClick(e)):
    #        text &"#{e} angle = {exercise.angle} vi = {exercise.speed} pos = ({exercise.pos.x}, {exercise.pos.x})"

proc addEventListeners*(state: var ParabolaState) = 
  window.addEventListener("resize", proc(event: Event) = 
    state.onResize()
  )

  document.addEventListener("keyup", proc(event: Event) =
    let event = KeyboardEvent(event)
    echo $event.key
    case $event.key
    of "t":
      state.calcTrajectory()
    of "ArrowRight":
      state.canon.rotate()
      state.calcTrajectory()
    of "ArrowLeft":
      state.canon.rotateBack()
      state.calcTrajectory()
    of "ArrowUp", " ":
      state.fireBullet()
    of "Backspace":
      state.reload()
    of "p":
      state.togglePause()
    #of "r":
    #  let exercise = exercises[curExercise]
    #  let bullet = bullets[currentBullet]
    #  Body.setPosition(bullet, jsVector(exercise.pos.x, state.normalizeY(exercise.pos.y)))
    #  Body.setAngle(bullet, degToRad(float(360 - exercise.angle)))
    #  calcTrajectory()
    #  exerciseStatus = csReady
    of "d":
      echo state
      print state.canon.bullet
  )
