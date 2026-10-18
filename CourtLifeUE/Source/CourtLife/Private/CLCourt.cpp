#include "CLCourt.h"

#include "CLCoreBridge.h"
#include "EngineUtils.h"
#include "CLShooting.h"

ACLCourt::ACLCourt()
{
	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("RimFloorPoint"));
}

courtlife::Vec2 ACLCourt::CourtFromWorld(const FVector& World) const
{
	const FVector Local = GetActorTransform().InverseTransformPositionNoScale(World) / CLUnitsPerFoot;
	// Unreal right (+Y) is the core's -x.
	return {-Local.Y, Local.X};
}

FVector ACLCourt::WorldFromCourt(courtlife::Vec2 Court, double HeightFt) const
{
	return GetActorTransform().TransformPositionNoScale(FVector(Court.z, -Court.x, HeightFt) * CLUnitsPerFoot);
}

float ACLCourt::DistanceToRimFt(const FVector& World) const
{
	const courtlife::Vec2 P = CourtFromWorld(World);
	return static_cast<float>(FMath::Sqrt(P.x * P.x + P.z * P.z));
}

bool ACLCourt::IsThree(const FVector& World) const
{
	return courtlife::IsThree(CourtFromWorld(World));
}

ACLCourt* ACLCourt::Find(const UObject* WorldContext)
{
	const UWorld* World = WorldContext ? WorldContext->GetWorld() : nullptr;
	if (!World) return nullptr;
	TActorIterator<ACLCourt> It(World);
	return It ? *It : nullptr;
}
