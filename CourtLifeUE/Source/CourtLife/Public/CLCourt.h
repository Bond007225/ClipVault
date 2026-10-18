#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "CLMath.h"
#include "CLCourt.generated.h"

/**
 * Place one per half court. The actor origin sits on the floor directly under
 * the rim centre and its forward (+X) points toward half court. Converts
 * between world space and the core's court space (feet, rim at origin).
 */
UCLASS()
class COURTLIFE_API ACLCourt : public AActor
{
	GENERATED_BODY()

public:
	ACLCourt();

	courtlife::Vec2 CourtFromWorld(const FVector& World) const;
	FVector WorldFromCourt(courtlife::Vec2 Court, double HeightFt = 0.0) const;
	FVector RimCenter() const { return WorldFromCourt({0.0, 0.0}, 10.0); }

	UFUNCTION(BlueprintPure, Category = "CourtLife|Court")
	float DistanceToRimFt(const FVector& World) const;

	UFUNCTION(BlueprintPure, Category = "CourtLife|Court")
	bool IsThree(const FVector& World) const;

	static ACLCourt* Find(const UObject* WorldContext);
};
