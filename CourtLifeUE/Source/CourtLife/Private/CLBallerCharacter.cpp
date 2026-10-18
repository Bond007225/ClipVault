#include "CLBallerCharacter.h"

#include "Camera/CameraComponent.h"
#include "CLAssets.h"
#include "CLBasketball.h"
#include "CLCoreBridge.h"
#include "CLCourt.h"
#include "CLCustomizationComponent.h"
#include "CLDribbleComponent.h"
#include "CLShotComponent.h"
#include "Components/CapsuleComponent.h"
#include "EnhancedInputComponent.h"
#include "EnhancedInputSubsystems.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/SpringArmComponent.h"

ACLBallerCharacter::ACLBallerCharacter()
{
	PrimaryActorTick.bCanEverTick = true;
	bUseControllerRotationYaw = false;
	GetCharacterMovement()->bOrientRotationToMovement = false;
	GetCharacterMovement()->RotationRate = FRotator(0.0, 720.0, 0.0);
	GetCharacterMovement()->BrakingDecelerationWalking = 2400.f;

	CameraBoom = CreateDefaultSubobject<USpringArmComponent>(TEXT("CameraBoom"));
	CameraBoom->SetupAttachment(RootComponent);
	CameraBoom->TargetArmLength = 17.0 * CLUnitsPerFoot;
	CameraBoom->SocketOffset = FVector(0.0, 0.0, 4.0 * CLUnitsPerFoot);
	CameraBoom->bUsePawnControlRotation = true;
	CameraBoom->bEnableCameraLag = true;
	CameraBoom->CameraLagSpeed = 6.f;

	Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("Camera"));
	Camera->SetupAttachment(CameraBoom, USpringArmComponent::SocketName);
	Camera->SetFieldOfView(50.f);

	Shot = CreateDefaultSubobject<UCLShotComponent>(TEXT("Shot"));
	Dribble = CreateDefaultSubobject<UCLDribbleComponent>(TEXT("Dribble"));
	Customization = CreateDefaultSubobject<UCLCustomizationComponent>(TEXT("Customization"));
}

void ACLBallerCharacter::BeginPlay()
{
	Super::BeginPlay();
	if (BallClass)
	{
		FActorSpawnParameters Params;
		Params.Owner = this;
		Ball = GetWorld()->SpawnActor<ACLBasketball>(BallClass, GetActorTransform(), Params);
	}
	ApplyBuild(Build.Attributes.Num() ? Build : UCLBuildLibrary::MakeDefaultBuild());
	AttachBallToHand();

	if (const APlayerController* PC = Cast<APlayerController>(GetController()))
	{
		if (UEnhancedInputLocalPlayerSubsystem* Input = ULocalPlayer::GetSubsystem<UEnhancedInputLocalPlayerSubsystem>(PC->GetLocalPlayer()))
		{
			if (MappingContext) Input->AddMappingContext(MappingContext, 0);
		}
	}
}

void ACLBallerCharacter::ApplyBuild(const FMyPlayerBuild& InBuild)
{
	Build = UCLBuildLibrary::NormalizeBuild(InBuild);
	Shot->Configure(Build, AnimSet);
	Dribble->Configure(Build, AnimSet);
	Customization->ApplyBuild(Build, Catalog);
	GetCharacterMovement()->MaxWalkSpeed = BaseWalkSpeed();
	GetCharacterMovement()->MaxAcceleration = FMath::Lerp(25.f, 55.f, CLBridge::Rating(Build, courtlife::Attr::Acceleration) / 99.f) * CLUnitsPerFoot;
	GetCharacterMovement()->JumpZVelocity = FMath::Lerp(14.f, 20.f, CLBridge::Rating(Build, courtlife::Attr::Vertical) / 99.f) * CLUnitsPerFoot;
}

float ACLBallerCharacter::BaseWalkSpeed() const
{
	const float Rating = static_cast<float>(CLBridge::Rating(Build, courtlife::Attr::SpeedWithBall));
	const float FtPerSec = FMath::GetMappedRangeValueClamped(FVector2f(40.f, 99.f), FVector2f(8.f, 14.f), Rating);
	return FtPerSec * CLUnitsPerFoot * (bSprinting ? 1.35f : 1.f);
}

void ACLBallerCharacter::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
	Super::SetupPlayerInputComponent(PlayerInputComponent);
	UEnhancedInputComponent* Input = Cast<UEnhancedInputComponent>(PlayerInputComponent);
	if (!Input) return;
	if (MoveAction) Input->BindAction(MoveAction, ETriggerEvent::Triggered, this, &ACLBallerCharacter::Move);
	if (SprintAction)
	{
		Input->BindAction(SprintAction, ETriggerEvent::Started, this, &ACLBallerCharacter::SprintStart);
		Input->BindAction(SprintAction, ETriggerEvent::Completed, this, &ACLBallerCharacter::SprintStop);
	}
	if (ShootAction)
	{
		Input->BindAction(ShootAction, ETriggerEvent::Started, this, &ACLBallerCharacter::ShootPressed);
		Input->BindAction(ShootAction, ETriggerEvent::Completed, this, &ACLBallerCharacter::ShootReleased);
	}
	for (int32 Slot = 0; Slot < ComboActions.Num(); ++Slot)
	{
		if (ComboActions[Slot]) Input->BindAction(ComboActions[Slot], ETriggerEvent::Started, this, &ACLBallerCharacter::ComboPressed, Slot);
	}
}

void ACLBallerCharacter::Move(const FInputActionValue& Value)
{
	if (Shot->IsShooting() || Dribble->IsInCombo() || !Controller) return;
	const FVector2D Axis = Value.Get<FVector2D>();
	const FRotator Yaw(0.0, Controller->GetControlRotation().Yaw, 0.0);
	AddMovementInput(FRotationMatrix(Yaw).GetUnitAxis(EAxis::X), Axis.Y);
	AddMovementInput(FRotationMatrix(Yaw).GetUnitAxis(EAxis::Y), Axis.X);
}

void ACLBallerCharacter::SprintStart(const FInputActionValue&)
{
	bSprinting = true;
	GetCharacterMovement()->MaxWalkSpeed = BaseWalkSpeed();
}

void ACLBallerCharacter::SprintStop(const FInputActionValue&)
{
	bSprinting = false;
	GetCharacterMovement()->MaxWalkSpeed = BaseWalkSpeed();
}

void ACLBallerCharacter::ShootPressed(const FInputActionValue&)
{
	if (!Ball || Ball->GetState() != ECLBallState::Held) return;
	Dribble->Cancel();
	Shot->BeginShot();
}

void ACLBallerCharacter::ShootReleased(const FInputActionValue&)
{
	Shot->ReleaseShot();
}

void ACLBallerCharacter::ComboPressed(int32 Slot)
{
	if (Shot->IsShooting() || !Ball || Ball->GetState() != ECLBallState::Held) return;
	Dribble->StartCombo(Slot);
}

void ACLBallerCharacter::OnShotStarted()
{
	GetCharacterMovement()->StopMovementImmediately();
	if (const ACLCourt* Court = ACLCourt::Find(this))
	{
		const FVector ToRim = Court->RimCenter() - GetActorLocation();
		SetActorRotation(FRotator(0.0, ToRim.Rotation().Yaw, 0.0));
	}
}

void ACLBallerCharacter::AttachBallToHand()
{
	if (!Ball) return;
	USkeletalMeshComponent* Body = GetMesh();
	if (Body->DoesSocketExist(BallBone))
	{
		Ball->Hold(Body, BallBone);
		return;
	}
	Ball->Hold(Body, Dribble->GetBallHand() == ECLHand::Right ? RightHandSocket : LeftHandSocket);
}

void ACLBallerCharacter::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	const ACLCourt* Court = ACLCourt::Find(this);
	if (!Court || !Ball) return;

	// Square up to the rim while handling the ball; the camera sits behind us.
	const bool bHasBall = Ball->GetState() == ECLBallState::Held;
	if (bHasBall && !Dribble->IsInCombo() && !Shot->IsShooting())
	{
		const double Yaw = (Court->RimCenter() - GetActorLocation()).Rotation().Yaw;
		SetActorRotation(FMath::RInterpTo(GetActorRotation(), FRotator(0.0, Yaw, 0.0), DeltaSeconds, 10.f));
		if (Controller)
		{
			Controller->SetControlRotation(FMath::RInterpTo(Controller->GetControlRotation(), FRotator(-12.0, Yaw, 0.0), DeltaSeconds, 4.f));
		}
		if (!GetMesh()->DoesSocketExist(BallBone)) AttachBallToHand();  // follow hand switches
	}
	else if (!bHasBall)
	{
		const FVector Vel = GetVelocity();
		if (Vel.SizeSquared2D() > 100.0) SetActorRotation(FRotator(0.0, Vel.Rotation().Yaw, 0.0));
		// Rebound: pick the ball up when it's close and low enough.
		const FVector Delta = Ball->GetActorLocation() - GetActorLocation();
		if (Ball->GetState() == ECLBallState::Loose && Delta.Size2D() < 3.0 * CLUnitsPerFoot && Delta.Z < 4.0 * CLUnitsPerFoot)
		{
			AttachBallToHand();
		}
	}
}
