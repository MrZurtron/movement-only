extends CharacterBody3D
class_name PlayerMovement

@export_category("Base Movement")
@export var speed : float = 20.0
var gravity : float = 20.0
var jump : float = 8.0
var cam_accel : float = 40.0
var mouse_sense : float = 0.05
var direction : Vector3
var gravity_vec : Vector3

# Nodes
@onready var head : Node3D = $Head
@onready var collider : CollisionShape3D = $CollisionShape3D
@onready var Camera: Camera3D = $Head/SpringArm3D/Camera
@onready var CeilingCheck: ShapeCast3D = $CeilingCheck

# Camera
@export_category("Procedural Camera Effects")
@export var jumpRotation : Vector3 = Vector3(-1.0, -0.5, 0.2)
@export var jumpAnimation : ProceduralCurve
@export var landPosition : Vector3 = Vector3(0, -0.15, 0)
@export var landPosAnimation : ProceduralCurve
@export var landRotation : Vector3 = Vector3(-0.5, 0, 0)
@export var landRotAnimation : ProceduralCurve
@export var slideTilt : float = -1.0
@export var slideAnimation : ProceduralCurve
@export var wallRunTilt : float = -3.0
@export var wallRunAnimation : ProceduralCurve
var rotationAnims: Array = []
var posAnims: Array = []
var tiltAnims: Array = []
@export_group("Field of View")
@export var base_fov: float = 75.0
@export var max_fov_stretch: float = 15.0
@export var fov_change_speed: float = 4.0
@export_category("Procedural Camera Effects")
@export var camera_tilt_lerp_speed: float = 6.0


# State Machine
enum MOVESTATES {GROUND, AIR, SLIDING, WALLRUNNING}
var currentState : MOVESTATES = MOVESTATES.AIR
var previousState : MOVESTATES = MOVESTATES.AIR

# Ground State
const floorSnapLength : float = 0.4
const floorAccel : float = 7.0
const floorDrag : float = 8.0

# Air State
const airSnapLength : float = 0.1
const airAccel : float = 0.5
const airSpeed : float = 16.0
const airDrag : float = 0.1
var gravityScale: float = 1.0 
const gravitySuspensionTime: float = 0.25 
const forward_air_control : float = 25.0 

# Air Strafing
@export var airStrafeCurve : Curve
const minStrafeAngle : float = 0.0
const maxStrafeAngle : float = 180.0
const airStrafeModifier : float = 1.0

# Jumping / Timing
var canJump : bool = true
var hasJumped : bool = false
const coyoteTime : float = 0.2
var jumpQueued : bool = false
var isInputLocked: bool = false
const inputLockTime: float = 0.10 

# Crouching
@onready var fullHeight : float = collider.shape.height
@onready var crouchHeight : float = fullHeight / 2.0
const heightLerpSpeed : float = 10.0
@onready var headOffset : float = head.position.y
var isCrouching : bool = false
const crouchSpeed : float = 8.0
const crouchAccel : float = 4.0

# Sliding
@export var slideDragCurve : Curve
@export var slopeAngleDragCurve : Curve
const slideAccel : float = 0.8
var slideCurvePoint : float = 0.0
const slideDragTime : float = 0.6
const startSlideThresh : float = 10.0
const endSlideSpeed : float = 5.0
const slideBoostForce : float = 10.0
const slideBoostTime : float = 2.0
var canSlideBoost : bool = true
const sharpAngleThreshold : float = 55.0
var previous_floor_normal : Vector3 = Vector3.UP
var is_accelerating_downhill: bool = false

# Wallrunning
@export var wallrunCurve : Curve
const wallrunHeight : float = 4.0
var wallrunStartVel : Vector3
var wallrunPoint : float = 0.0
const wallrunTime : float = 2.0
const wallRunResetTime : float = 0.5
var hasLeftWallRun : bool = false
var hasRightWallRun : bool = false
var leftWallRun : bool = true
var prevWallNormal : Vector3
var prevWallRunPoint : Vector3 = Vector3(-INF, -INF, -INF)
var last_wall_normal : Vector3 = Vector3.ZERO
var last_wall_jump_normal : Vector3 = Vector3.ZERO
var wallrun_cooldown_timer : float = 1.0
const wallrun_cooldown_duration : float = 0.5
@export var wallrun_inherent_boost : float = 4.0
@export_range(0.0, 180.0, 0.5, "suffix:°") var same_wall_prevent_angle: float = 0.0
var can_wallrun_again: bool = true

# Wall Bounce Anti-Spam
var active_bounced_wall_normal: Vector3 = Vector3.ZERO
var wall_bounce_prevention_timer: float = 0.0
@export var same_wall_bounce_cooldown: float = 2.0

# Dash
var can_dash: bool = true
var is_dashing: bool = false
var dash_timer: float = 0.0
@export var dash_speed: float = 30.0 
@export var dash_duration: float = 0.5
@export var dash_cooldown: float = 2.0
@export var post_dash_gravity_multiplier: float = 2.0 
var apply_post_dash_gravity: bool = false

# Signals
signal justJumped; signal justLanded;
signal startSlide; signal endSlide;
signal startWallRun(isLeft : bool); signal endWallRun(isLeft : bool);

# Camera Shake
@export_category("Camera Bobbing")
@export var bob_frequency_walk: float = 12.0   
@export var bob_amplitude_walk: float = 0.06    
@export var bob_frequency_crouch: float = 8.0   
@export var bob_amplitude_crouch: float = 0.04  
var bob_time: float = 0.0

func _ready() -> void:
	headOffset = head.position.y
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	wall_min_slide_angle = deg_to_rad(0.0) 
	floor_max_angle = deg_to_rad(60.0) 
	
	justJumped.connect(_startJumpAnimation)
	justLanded.connect(_startLandAnimation)
	startSlide.connect(_startSlideAnim)
	endSlide.connect(_endSlideAnim)
	startWallRun.connect(_startWallRunAnim)
	endWallRun.connect(_endWallRunAnim)
	
	rotationAnims = [jumpAnimation, landRotAnimation]
	posAnims = [landPosAnimation]
	tiltAnims = [slideAnimation, wallRunAnimation]
	
	if jumpAnimation: jumpAnimation.set_targets(Vector3.ZERO, jumpRotation, Vector3.ZERO)
	if landPosAnimation: landPosAnimation.set_targets(Vector3.ZERO, landPosition, Vector3.ZERO)
	if landRotAnimation: landRotAnimation.set_targets(Vector3.ZERO, landRotation, Vector3.ZERO)
	if slideAnimation: slideAnimation.set_targets(0.0, slideTilt, slideTilt)
	if wallRunAnimation: wallRunAnimation.set_targets(0.0, wallRunTilt, wallRunTilt)
	if Camera:
		Camera.fov = base_fov

func _process(delta: float) -> void:
	if not Camera:
		return
	for anim in rotationAnims:
		if is_instance_valid(anim) and anim.is_running():
			Camera.rotation_degrees = anim.step(delta)
	var final_target_tilt: float = 0.0
	if currentState == MOVESTATES.WALLRUNNING:
		if is_instance_valid(wallRunAnimation):
			final_target_tilt = wallRunAnimation.targets.get("max", wallRunTilt)
	elif currentState == MOVESTATES.SLIDING:
		final_target_tilt = slideTilt
	Camera.rotation_degrees.z = lerp(Camera.rotation_degrees.z, final_target_tilt, camera_tilt_lerp_speed * delta)

func _physics_process(delta : float) -> void:
	# Tick down the wallrun lock-out timer
	if wallrun_cooldown_timer > 0.0:
		wallrun_cooldown_timer -= delta

	if wall_bounce_prevention_timer > 0.0:
		wall_bounce_prevention_timer -= delta
		if wall_bounce_prevention_timer <= 0.0:
			active_bounced_wall_normal = Vector3.ZERO

	match currentState:
		MOVESTATES.GROUND:
			ground(delta)
		MOVESTATES.AIR:
			air(delta)
		MOVESTATES.SLIDING:
			slide(delta)
		MOVESTATES.WALLRUNNING:
			wallrun(delta)
			
	# Jump tracking mechanics
	if (Input.is_action_just_pressed("jump") or jumpQueued) and canJump:
		canJump = false
		hasJumped = true
		jumpQueued = false
		emit_signal("justJumped")
		if currentState != MOVESTATES.AIR:
			changeState(MOVESTATES.AIR)
			
	# Dash execution loops
	if is_dashing:
		execute_dash(delta)
	else:
		if Input.is_action_just_pressed("dash"):
			start_dash()

	# ====================================================================
	# CAMERA TRACKING & BOB PHYSICS LAYER 
	# ====================================================================
	if Camera and head:
		var horizontal_speed: float = Vector3(velocity.x, 0.0, velocity.z).length()
		var procedural_offset_y: float = 0.0
		if is_instance_valid(landPosAnimation) and landPosAnimation.is_running():
			procedural_offset_y = landPosAnimation.step(delta).y
		var current_base_head_y: float = headOffset / 2.0 if isCrouching else headOffset
		var target_y: float = current_base_head_y + procedural_offset_y
		
		if is_on_floor() and horizontal_speed > 0.1 and currentState == MOVESTATES.GROUND:
			var current_freq: float = bob_frequency_crouch if isCrouching else bob_frequency_walk
			var current_amp: float = bob_amplitude_crouch if isCrouching else bob_amplitude_walk
			bob_time += delta * horizontal_speed * (current_freq * 0.1)
			var new_y_offset: float = sin(bob_time) * current_amp
			
			# Lerp the base stance height smoothly while adding the head bobbing offset on top
			var blended_base_y = lerp(head.position.y - new_y_offset, current_base_head_y + procedural_offset_y, heightLerpSpeed * delta)
			head.position.y = blended_base_y + new_y_offset
		else:
			# Smoothly transition when sliding, standing still, or in mid-air
			bob_time = 0.0
			head.position.y = lerp(head.position.y, target_y, heightLerpSpeed * delta)
			
		Camera.position = Vector3.ZERO

		# ====================================================================
		# DYNAMIC FOV EFFECTS
		# ====================================================================
		# Calculate speed factor relative to normal base movement speed
		var speed_percentage: float = clamp(horizontal_speed / speed, 0.0, 2.0)
		var target_fov: float = base_fov + (speed_percentage * max_fov_stretch)
		
		# Smoothly update camera field of view
		Camera.fov = lerp(Camera.fov, target_fov, fov_change_speed * delta)

func ground(delta : float) -> void:
	isCrouching = handleCrouch(delta)
	gravity_vec = Vector3.ZERO
	if is_on_floor():
		var current_normal = get_floor_normal()
		var surface_angle_change = rad_to_deg(previous_floor_normal.angle_to(current_normal))
		if surface_angle_change > sharpAngleThreshold:
			floor_snap_length = 0.0
		else:
			floor_snap_length = floorSnapLength
		previous_floor_normal = current_normal
	else:
		floor_snap_length = floorSnapLength
	if !isCrouching or (isCrouching and velocity.length() > startSlideThresh):
		move(delta, floorAccel, floorDrag)
		if isCrouching:
			toSlide()
	else:
		move(delta, crouchAccel, floorDrag)
	groundToAir()

func air(delta : float) -> void:
	isCrouching = handleCrouch(delta, false, true)
	floor_snap_length = airSnapLength
	if hasJumped:
		gravity_vec = Vector3.UP * jump
		hasJumped = false
	else:
		gravity_vec = Vector3.DOWN * gravity * gravityScale * delta
	move(delta, airAccel, airDrag)

	if is_on_floor():
		can_wallrun_again = true
		isInputLocked = false
		gravityScale = 1.0 
		last_wall_jump_normal = Vector3.ZERO 
		last_wall_normal = Vector3.ZERO 
		wallrun_cooldown_timer = 0.0 
		
		# NEW: Reset wall bounce history upon touching the ground
		active_bounced_wall_normal = Vector3.ZERO
		wall_bounce_prevention_timer = 0.0
		
		if isCrouching and velocity.length() > startSlideThresh:
			toSlide()
		else:
			changeState(MOVESTATES.GROUND)
			hasLeftWallRun = false
			hasRightWallRun = false
			emit_signal("justLanded")
		canJump = true
		
	if Input.is_action_just_pressed("jump"):
		queueJump()
		
	if is_on_wall() and not is_on_floor():
		var wall_normal : Vector3 = get_wall_normal()
		
		# NEW: If the player hits a completely different wall, clear the bounce restriction early
		if active_bounced_wall_normal.length_squared() > 0.0 and active_bounced_wall_normal.dot(wall_normal) < 0.8:
			active_bounced_wall_normal = Vector3.ZERO
			wall_bounce_prevention_timer = 0.0
		
		# Convert our inspector degrees into a dot product threshold comparison limit
		var angle_threshold_dot = cos(deg_to_rad(same_wall_prevent_angle))
		
		# Wall Jump / Kickback
		if Input.is_action_just_pressed("jump") and not Input.is_action_pressed("hold"):
			# NEW: Block the jump if the player tries to spam the same wall before the timer expires
			if wall_bounce_prevention_timer > 0.0 and active_bounced_wall_normal.dot(wall_normal) > 0.95:
				return

			# DYNAMIC LOCKOUT: Skips check if angle is set to 0, otherwise applies your custom limit
			if same_wall_prevent_angle > 0.01 and last_wall_normal.length_squared() > 0.0 and last_wall_normal.dot(wall_normal) > angle_threshold_dot:
				return
				
			# NEW: Set up the restriction variables for this wall jump
			active_bounced_wall_normal = wall_normal
			wall_bounce_prevention_timer = same_wall_bounce_cooldown
				
			last_wall_normal = wall_normal
			prevWallRunPoint = position
			last_wall_jump_normal = wall_normal 
			
			wallrun_cooldown_timer = wallrun_cooldown_duration
			
			var outward_push : Vector3 = wall_normal * 12.0
			var current_h_vel = Vector3(velocity.x, 0.0, velocity.z)
			var preserved_vel = current_h_vel - current_h_vel.project(wall_normal)
			var final_h_vel = preserved_vel + outward_push
			
			var max_chain_speed = speed * 1.5 
			if final_h_vel.length() > max_chain_speed:
				final_h_vel = final_h_vel.normalized() * max_chain_speed
				
			velocity.x = final_h_vel.x
			velocity.z = final_h_vel.z
			velocity.y = jump * 1.1 
			
			isInputLocked = true
			executeAfterTime(inputLockTime * 2.5, func(): 
				isInputLocked = false 
			)
			gravityScale = 0.5
			executeAfterTime(gravitySuspensionTime, func(): 
				gravityScale = 1.0 
			)
			return
			
		# Wallrun Entry Check
		if Input.is_action_pressed("hold"):
			# FIXED: Use a direct boolean flag lockout
			if not can_wallrun_again or wallrunPoint >= 1.0:
				return
				
			var leftWall : bool = isWallRunningLeft(get_last_slide_collision().get_position())
			if not ((leftWall and hasLeftWallRun) or (!leftWall and hasRightWallRun)):
				wallrunPoint = 0.0
				if leftWall:
					hasLeftWallRun = true
					hasRightWallRun = false
				else:
					hasLeftWallRun = false
					hasRightWallRun = true
			elif position.y > prevWallRunPoint.y:
				return
			changeState(MOVESTATES.WALLRUNNING)
			wallrunStartVel = velocity

func slide(delta : float) -> void:
	if not is_on_floor():
		changeState(MOVESTATES.AIR)
		slideCurvePoint = 0.0
		return

	var is_trapped : bool = CeilingCheck and CeilingCheck.is_colliding()

	# If the user releases crouch and isn't trapped under a ceiling, return to standing ground
	if not Input.is_action_pressed("crouch") and not is_trapped:
		changeState(MOVESTATES.GROUND)
		slideCurvePoint = 0.0
		return
		
	isCrouching = handleCrouch(delta, true)
	
	var current_normal = get_floor_normal()
	var surface_angle_change = rad_to_deg(previous_floor_normal.angle_to(current_normal))
	if surface_angle_change > sharpAngleThreshold:
		floor_snap_length = 0.0
	else:
		floor_snap_length = max(floorSnapLength, velocity.length() * delta * 2.0)
	previous_floor_normal = current_normal
	
	var floor_angle := get_floor_angle()
	var floor_angle_deg := rad_to_deg(floor_angle)
	var min_slope_threshold : float = 3.0
	if floor_angle_deg < min_slope_threshold:
		floor_angle = 0.0
	var angleCurveSamplePoint := floor_angle / floor_max_angle
	var floor_normal := get_floor_normal()
	var downhill_dir := Vector3(floor_normal.x, 0, floor_normal.z).normalized()
	
	var velocity_dot_downhill = velocity.normalized().dot(downhill_dir)
	var isSlideDownward : bool = velocity_dot_downhill > -0.2 and floor_angle > 0.0
	var isSlideUpward : bool = velocity_dot_downhill <= -0.2 and floor_angle > 0.0
	
	gravity_vec = Vector3.DOWN * gravity * delta
	var slideDrag : float = 0.0
	
	if isSlideDownward:
		is_accelerating_downhill = true
		slideCurvePoint = max(0.0, slideCurvePoint - delta) 
		var gravity_force = 4.0 * (1.0 + (angleCurveSamplePoint * 4.0))
		velocity += downhill_dir * gravity_force * delta
		slideDrag = airDrag 
	else:
		is_accelerating_downhill = false
		if slideCurvePoint < 1.0:
			slideCurvePoint += delta / slideDragTime
		else:
			slideCurvePoint = 1.0
		var sampled_drag: float = 0.1
		if slideDragCurve and slopeAngleDragCurve:
			sampled_drag = slideDragCurve.sample(slideCurvePoint) * slopeAngleDragCurve.sample(angleCurveSamplePoint)
		slideDrag = sampled_drag if sampled_drag > 0.01 else 25.0
		
		if isSlideUpward:
			var uphill_braking_force = 45.0 * angleCurveSamplePoint
			velocity = velocity.move_toward(Vector3.ZERO, uphill_braking_force * delta)

	move(delta, slideAccel, slideDrag)
	
	var dynamic_max_speed = speed + (angleCurveSamplePoint * 35.0)
	if isSlideDownward:
		if velocity.length() > dynamic_max_speed:
			velocity = velocity.normalized() * dynamic_max_speed
	else:
		# SPEED EVALUATION EXIT
		if velocity.length() < endSlideSpeed:
			# If trapped under an object, return to GROUND state but keep crouching forced true
			if is_trapped:
				changeState(MOVESTATES.GROUND)
				isCrouching = handleCrouch(delta, true)
				slideCurvePoint = 0.0
			else:
				var must_clear_crouch : bool = not Input.is_action_pressed("crouch")
				isCrouching = handleCrouch(delta, false, must_clear_crouch)
				changeState(MOVESTATES.GROUND)
				slideCurvePoint = 0.0

func wallrun(delta : float) -> void:
	var leftWallNormal : Vector3 = get_wall_normal().rotated(Vector3.UP, PI/2)
	var rightWallNormal : Vector3 = get_wall_normal().rotated(Vector3.UP, -PI/2)
	var newDir : Vector3 = leftWallNormal if leftWallNormal.angle_to(wallrunStartVel) < rightWallNormal.angle_to(wallrunStartVel) else rightWallNormal
	
	if is_on_floor():
		changeState(MOVESTATES.GROUND)
		resetWallRun()
		return
		
	# Manual Jump Out
	if Input.is_action_just_pressed("jump"):
		var wall_normal = get_wall_normal()
		prevWallRunPoint = position
		last_wall_normal = wall_normal
		
		changeState(MOVESTATES.AIR)
		
		var outward_push : Vector3 = wall_normal * 14.0
		var current_h_vel = Vector3(velocity.x, 0.0, velocity.z)
		var combined_jump = current_h_vel + outward_push
		
		var max_chain_speed = speed * 1.5
		if combined_jump.length() > max_chain_speed:
			combined_jump = combined_jump.normalized() * max_chain_speed
			
		velocity.x = combined_jump.x
		velocity.z = combined_jump.z
		velocity.y = jump * 1.2
		
		isInputLocked = true
		executeAfterTime(inputLockTime * 2.5, func(): 
			isInputLocked = false 
		)
		
		gravityScale = 0.5
		executeAfterTime(gravitySuspensionTime, func(): 
			gravityScale = 1.0 
		)
		resetWallRun()
		return
		
	# Releasing Hold Button Exit
	if not Input.is_action_pressed("hold"):
		can_wallrun_again = false
		executeAfterTime(wallrun_cooldown_duration, func(): can_wallrun_again = true)
		changeState(MOVESTATES.AIR)
		resetWallRun()
		return
		
	# Process the Wallrun Time Limit Clock
	if wallrunPoint < 1.0 and is_on_wall_only():
		wallrunPoint += delta / wallrunTime
	else:
		# FIXED: Trigger explicit cooldown lockout here
		can_wallrun_again = false
		executeAfterTime(wallrun_cooldown_duration, func(): can_wallrun_again = true)
		
		changeState(MOVESTATES.AIR)
		resetWallRun()
		return

	# Maintain our exact calculated forward vector from entry
	var final_wall_speed = wallrunStartVel.length()
	var horizontal_vel = newDir.normalized() * final_wall_speed
	
	velocity.x = horizontal_vel.x
	velocity.z = horizontal_vel.z
	velocity.y = 0.0
	
	velocity -= get_wall_normal() * 2.0
	move_and_slide()
	prevWallNormal = get_wall_normal()

func changeState(newState : MOVESTATES) -> void:
	previousState = currentState
	currentState = newState
	
	if previousState == MOVESTATES.SLIDING:
		emit_signal("endSlide")
			
	if currentState == MOVESTATES.SLIDING:
		emit_signal("startSlide")
			
	if currentState == MOVESTATES.WALLRUNNING:
		emit_signal("startWallRun", leftWallRun)
		
	if previousState == MOVESTATES.WALLRUNNING:
		emit_signal("endWallRun", leftWallRun)

func queueJump() -> void:
	jumpQueued = true
	await get_tree().create_timer(coyoteTime).timeout
	jumpQueued = false

func groundToAir() -> bool:
	if !is_on_floor():
		changeState(MOVESTATES.AIR)
		if canJump:
			executeAfterTime(coyoteTime, func():
				if !is_on_floor(): 
					canJump = false
			)
		return true
	return false

func toSlide() -> bool:
	if canSlideBoost:
		var slide_direction : Vector3 = direction
		if slide_direction == Vector3.ZERO:
			slide_direction = velocity.normalized()
		slide_direction.y = 0.0
		slide_direction = slide_direction.normalized()
		if slide_direction == Vector3.ZERO:
			slide_direction = -Camera.global_transform.basis.z
			slide_direction.y = 0.0
			slide_direction = slide_direction.normalized()
		
		# Boost based on whether player is moving fast or slow
		if velocity.length() > startSlideThresh:
			velocity = slide_direction * (velocity.length() * 1.4)
		else:
			velocity = slide_direction * (speed + 12.0)
			
		canSlideBoost = false
		executeAfterTime(slideBoostTime, func(): canSlideBoost = true)
	
	changeState(MOVESTATES.SLIDING)
	slideCurvePoint = 0.0
	return true

func executeAfterTime(time : float, function : Callable) -> void:
	await get_tree().create_timer(time).timeout
	function.call()

func applyForce(force : Vector3) -> void:
	velocity += force

func slowMovement(amount : float) -> void:
	velocity *= amount

func handleCrouch(delta : float, forceCrouch : bool = false, forceUncrouch : bool = false) -> bool:
	var height : float = collider.shape.height
	var crouching : bool = Input.is_action_pressed("crouch") or forceCrouch
	if forceUncrouch:
		crouching = false
	if not crouching and CeilingCheck.is_colliding():
		crouching = true
	var target_height : float = crouchHeight if crouching else fullHeight
	if not is_equal_approx(height, target_height):
		collider.shape.height = lerp(height, target_height, delta * heightLerpSpeed)
		var height_difference = (collider.shape.height - height)
		collider.position.y += height_difference / 2.0
	var current_base_head_y: float = headOffset / 2.0 if crouching else headOffset
	head.position.y = lerp(head.position.y, current_base_head_y, delta * heightLerpSpeed)
	return crouching

func move(delta : float, accel : float, drag : float, move_speed : float = -1.0) -> void:
	var final_speed : float = speed if move_speed < 0.0 else move_speed
	direction = Vector3.ZERO
	if not isInputLocked:
		var h_rot : float = global_transform.basis.get_euler().y
		var f_input : float = Input.get_axis("forward", "backward")
		var h_input : float = Input.get_action_strength("right") - Input.get_action_strength("left")
		direction = Vector3(h_input, 0, f_input).rotated(Vector3.UP, h_rot).normalized()
	var wish_vel : Vector3 = direction * final_speed

	match currentState:
		MOVESTATES.AIR:
			var angle_diff : float = rad_to_deg(getHorizontalAngle(velocity, wish_vel))
			var samplePoint := (angle_diff - minStrafeAngle) / maxStrafeAngle
			if airStrafeCurve:
				wish_vel *= 1.0 + (airStrafeCurve.sample(samplePoint) * airStrafeModifier)

	if currentState == MOVESTATES.GROUND and isCrouching:
		wish_vel = direction * crouchSpeed
		
	if direction.length() > 0:
		match currentState:
			MOVESTATES.SLIDING:
				if is_on_wall():
					velocity = velocity.slide(get_wall_normal())
				
				if is_accelerating_downhill:
					var speed_before_steering = velocity.length()
					var combined_dir = (velocity.normalized() + (direction * 0.3)).normalized()
					velocity = combined_dir * speed_before_steering
				else:
					var sample_drag = slideDragCurve.sample(slideCurvePoint) if slideDragCurve else 0.2
					var newVelLength : float = velocity.lerp(Vector3.ZERO, sample_drag * delta).length()
					var newVelDir : Vector3 = lerp(velocity.normalized(), wish_vel.normalized(), accel * delta)
					velocity = newVelDir.normalized() * newVelLength
			
			MOVESTATES.AIR:
				velocity = lerp(velocity, wish_vel, accel * delta)
				if not isInputLocked and Input.is_action_pressed("forward"):
					var look_rot : float = global_transform.basis.get_euler().y
					var forward_dir := Vector3.FORWARD.rotated(Vector3.UP, look_rot).normalized()
					var current_h_speed = Vector3(velocity.x, 0, velocity.z).length()
					var target_h_vel = forward_dir * max(current_h_speed, airSpeed)
					var final_h = Vector3(velocity.x, 0, velocity.z).lerp(target_h_vel, 5.0 * delta)
					velocity.x = final_h.x
					velocity.z = final_h.z
			_:
				velocity = lerp(velocity, wish_vel, accel * delta)
	else:
		if not currentState == MOVESTATES.SLIDING:
			velocity = lerp(velocity, wish_vel, drag * delta)
		else:
			if is_on_wall():
				velocity = velocity.slide(get_wall_normal())
			var slide_drag_mod = slideDragCurve.sample(slideCurvePoint) if slideDragCurve else 0.4
			velocity = velocity.move_toward(Vector3.ZERO, slide_drag_mod * drag * 2.0 * delta)
			
	velocity += gravity_vec
	move_and_slide()
	if not isInputLocked and currentState != MOVESTATES.WALLRUNNING:
		velocity += gravity_vec

func isWallRunningLeft(collisionPoint : Vector3) -> bool:
	var localCollision : Vector3 = head.to_local(collisionPoint)
	leftWallRun = not localCollision.x >= 0
	return localCollision.x < 0

func resetWallRun() -> void:
	# Clear side restrictions immediately upon a proper reset cycle
	hasLeftWallRun = false
	hasRightWallRun = false
	if currentState != MOVESTATES.WALLRUNNING:
		wallrunPoint = 0.0
	prevWallNormal = Vector3.UP

func getHorizontalAngle(vec1 : Vector3, vec2 : Vector3) -> float:
	var v1 := Vector3(vec1.x, 0.0, vec1.z)
	var v2 := Vector3(vec2.x, 0.0, vec2.z)
	return abs(v1.angle_to(v2))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sense * 0.05)
		if head:
			head.rotate_x(-event.relative.y * mouse_sense * 0.05)
			head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func start_dash() -> void:
	if not can_dash or is_dashing:
		return
	is_dashing = true
	can_dash = false
	apply_post_dash_gravity = false
	dash_timer = dash_duration
	var camera_forward: Vector3 = -Camera.global_transform.basis.z
	velocity = velocity + (camera_forward.normalized() * dash_speed)

func execute_dash(delta: float) -> void:
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing = false
			apply_post_dash_gravity = true
			_start_cooldown()
		return 
	if apply_post_dash_gravity:
		if is_on_floor():
			apply_post_dash_gravity = false
		else:
			velocity.y -= gravity * post_dash_gravity_multiplier * delta

func _start_cooldown() -> void:
	await get_tree().create_timer(dash_cooldown).timeout
	can_dash = true




# ==== CAMERA FUNCTIONS === #

func _startJumpAnimation() -> void:
	if is_instance_valid(landPosAnimation): landPosAnimation.force_stop()
	if is_instance_valid(landRotAnimation): landRotAnimation.force_stop()
	if is_instance_valid(jumpAnimation) and Camera: jumpAnimation.start(Camera.rotation_degrees)
	
func _startLandAnimation() -> void:
	if is_instance_valid(jumpAnimation): jumpAnimation.force_stop()
	if is_instance_valid(landPosAnimation) and Camera: landPosAnimation.start(Camera.position)
	if is_instance_valid(landRotAnimation) and Camera: landRotAnimation.start(Camera.rotation_degrees)

func _startTilt(anim : ProceduralCurve) -> void:
	if not is_instance_valid(anim) or not Camera: return
	for i in rotationAnims:
		if is_instance_valid(i): i.force_stop()
		
	if anim.targets.get("min") is Vector3:
		anim.start(Camera.rotation_degrees)
	else:
		anim.start(Camera.rotation_degrees.z)

func _endTilt(anim : ProceduralCurve) -> void:
	if not is_instance_valid(anim) or not Camera: return
	if anim.targets.get("min") is Vector3:
		anim.start_backwards(Camera.rotation_degrees)
	else:
		anim.start_backwards(Camera.rotation_degrees.z)

func _startWallRunAnim(left : bool) -> void:
	wallRunTilt = -wallRunTilt if (wallRunTilt < 0 and !left) or (wallRunTilt > 0 and left) else wallRunTilt
	if is_instance_valid(wallRunAnimation):
		wallRunAnimation.targets["max"] = wallRunTilt
		wallRunAnimation.targets["snap"] = wallRunTilt
		_startTilt(wallRunAnimation)

func _endWallRunAnim(_left : bool) -> void:
	_endTilt(wallRunAnimation)

func _startSlideAnim() -> void:
	_startTilt(slideAnimation)

func _endSlideAnim() -> void:
	_endTilt(slideAnimation)
