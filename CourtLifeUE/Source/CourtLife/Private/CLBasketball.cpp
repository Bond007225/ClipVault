#include "CLBasketball.h"

#include "CLCoreBridge.h"
#include "CLCourt.h"
#include "Components/StaticMeshComponent.h"
#include "CLShooting.h"

ACLBasketball::ACLBasketball()
{
	PrimaryActorTick.bCanEverTick = true;
	Mesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Mesh"));
	Mesh->SetCollisionProfileName(TEXT("PhysicsActor"));
	Mesh->SetSimulatePhysics(false);
	RootComponent = Mesh;
}

void ACLBasketball::Hold(USceneComponent* Hand, FName Socket)
{
	State = ECLBallState::Held;
	Mesh->SetSimulatePhysics(false);
	Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);  // don't shove the handler
	AttachToComponent(Hand, FAttachmentTransformRules::SnapToTargetNotIncludingScale, Socket);
}

void ACLBasketball::Shoot(bool bMake, int32 Points, float DistanceFt, float FlightTimeSec)
{
	Court = ACLCourt::Find(this);
	if (!Court.IsValid()) return;
	DetachFromActor(FDetachmentTransformRules::KeepWorldTransform);
	Mesh->SetSimulatePhysics(false);
	Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);  // scripted arc until it reaches the rim

	FVector Target = Court->RimCenter() + FVector(0, 0, 0.15 * CLUnitsPerFoot);
	if (!bMake)
	{
		// Clank: aim at a random point on the rim itself.
		const double A = FMath::FRandRange(0.0, 2.0 * PI);
		const double R = courtlife::kRimRadiusFt * 0.95 * CLUnitsPerFoot;
		Target = Court->RimCenter() + FVector(FMath::Cos(A) * R, FMath::Sin(A) * R, 0.1 * CLUnitsPerFoot);
	}
	const double G = GetWorld()->GetGravityZ();
	// Finishes pass a short flight time (a dunk is thrown straight through); jumpers arc by distance.
	FlightTime = FlightTimeSec > 0.f ? FlightTimeSec : 0.75f + DistanceFt * 0.028f;
	const FVector Start = GetActorLocation();
	Velocity = (Target - Start) / FlightTime;
	Velocity.Z = (Target.Z - Start.Z - 0.5 * G * FlightTime * FlightTime) / FlightTime;
	FlightElapsed = 0.f;
	bWillMake = bMake;
	PendingPoints = Points;
	State = ECLBallState::Flight;
}

void ACLBasketball::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	if (State != ECLBallState::Flight) return;
	FlightElapsed += DeltaSeconds;
	Velocity.Z += GetWorld()->GetGravityZ() * DeltaSeconds;
	SetActorLocation(GetActorLocation() + Velocity * DeltaSeconds);
	if (FlightElapsed < FlightTime || !Court.IsValid()) return;

	if (bWillMake)
	{
		State = ECLBallState::ThroughNet;
		SetActorLocation(Court->RimCenter());
		OnBasket.Broadcast(PendingPoints);
		BecomeLoose(FVector(0, 0, -6.0 * CLUnitsPerFoot));
	}
	else
	{
		FVector Out = GetActorLocation() - Court->RimCenter();
		Out.Z = 0;
		Out = Out.GetSafeNormal();
		const double Kick = FMath::FRandRange(6.0, 12.0) * CLUnitsPerFoot;
		BecomeLoose(Out * Kick + FVector(0, 0, FMath::FRandRange(6.0, 12.0) * CLUnitsPerFoot));
	}
}

void ACLBasketball::Deflect(const FVector& InVelocity)
{
	DetachFromActor(FDetachmentTransformRules::KeepWorldTransform);
	BecomeLoose(InVelocity);
}

void ACLBasketball::BecomeLoose(const FVector& InVelocity)
{
	Mesh->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
	Mesh->SetSimulatePhysics(true);
	Mesh->SetPhysicsLinearVelocity(InVelocity);
	OnLoose.Broadcast();
	State = ECLBallState::Loose;
}
