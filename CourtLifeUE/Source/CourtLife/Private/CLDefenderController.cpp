#include "CLDefenderController.h"

#include "Animation/AnimInstance.h"
#include "CLCoreBridge.h"
#include "CLCourt.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"

ACLDefenderController::ACLDefenderController()
{
	PrimaryActorTick.bCanEverTick = true;
}

void ACLDefenderController::OnPossess(APawn* InPawn)
{
	Super::OnPossess(InPawn);
	if (const ACLCourt* Court = ACLCourt::Find(this))
	{
		State.pos = Court->CourtFromWorld(InPawn->GetActorLocation());
		State.seen = State.pos;
	}
}

void ACLDefenderController::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	ACharacter* Me = Cast<ACharacter>(GetPawn());
	const ACLCourt* Court = ACLCourt::Find(this);
	if (!Me || !Court || !Handler.IsValid()) return;

	State.perimeterDefense = PerimeterDefense;
	State.speed = Speed;
	State.acceleration = Acceleration;
	// Physics/collision own the real position; the brain only decides intent.
	State.pos = Court->CourtFromWorld(Me->GetActorLocation());
	const courtlife::Vec2 HandlerPos = Court->CourtFromWorld(Handler->GetActorLocation());
	courtlife::StepDefender(State, HandlerPos, {0.0, 0.0}, DeltaSeconds);

	const courtlife::Vec2 Here = Court->CourtFromWorld(Me->GetActorLocation());
	const FVector Desired = Court->WorldFromCourt({Here.x + State.vel.x, Here.z + State.vel.z}) - Court->WorldFromCourt(Here);
	const double SpeedFt = FMath::Sqrt(State.vel.x * State.vel.x + State.vel.z * State.vel.z);
	UCharacterMovementComponent* Move = Me->GetCharacterMovement();
	Move->MaxWalkSpeed = FMath::Lerp(9.f, 14.f, (Speed - 40) / 59.f) * CLUnitsPerFoot;
	if (State.stumble <= 0 && SpeedFt > 0.2)
	{
		Me->AddMovementInput(Desired.GetSafeNormal2D(), FMath::Clamp(SpeedFt * CLUnitsPerFoot / Move->MaxWalkSpeed, 0.0, 1.0));
	}
	// Always face the ball handler, sliding laterally like a real defender.
	const FVector ToHandler = Handler->GetActorLocation() - Me->GetActorLocation();
	Me->SetActorRotation(FMath::RInterpTo(Me->GetActorRotation(), FRotator(0.0, ToHandler.Rotation().Yaw, 0.0), DeltaSeconds, 12.f));
}

void ACLDefenderController::ReactToCombo(float Effectiveness, int32 BallHandle)
{
	if (!GetPawn() || !Handler.IsValid() || State.stumble > 0) return;
	const double Dist = FVector::Dist2D(GetPawn()->GetActorLocation(), Handler->GetActorLocation()) / CLUnitsPerFoot;
	const double Stumble = courtlife::AnkleBreakCheck(Effectiveness, BallHandle, PerimeterDefense, Dist, FMath::FRand());
	if (Stumble > 0)
	{
		State.stumble = Stumble;
		PlayMontage(StumbleMontage);
	}
}

void ACLDefenderController::ReactToShot()
{
	ACharacter* Me = Cast<ACharacter>(GetPawn());
	const ACLCourt* Court = ACLCourt::Find(this);
	if (!Me || !Court || !Handler.IsValid()) return;
	if (courtlife::StartContest(State, Court->CourtFromWorld(Handler->GetActorLocation())))
	{
		Me->Jump();
		PlayMontage(ContestMontage);
	}
}

void ACLDefenderController::PlayMontage(UAnimMontage* Montage)
{
	const ACharacter* Me = Cast<ACharacter>(GetPawn());
	UAnimInstance* Anim = Me ? Me->GetMesh()->GetAnimInstance() : nullptr;
	if (Anim && Montage) Anim->Montage_Play(Montage);
}
